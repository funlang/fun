// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ado-odbc-unx: the unixODBC backend of lib-ado-unx.
//
// lib-ado-unx historically spoke only SQLite. Windows ADO reaches every
// database through an ODBC provider; this unit gives Unix the same shape, so
// the ORM stack can talk to MySQL, PostgreSQL, SQL Server, DB2 or a remote
// SQLite file through one driver manager instead of growing one backend per
// database.
//
// It is loaded by lib-ado-unx only when the connection string selects ODBC:
// 'odbc:...', or a string containing 'DRIVER=' or 'DSN='. Everything else
// stays on the embedded SQLite path (zero configuration, no system driver).
//
// Native handles are module-level lazily-created getapi objects: a host without
// libodbc can still load lib-ado-unx and use SQLite. The whole unit uses the
// ODBC 3.x handle API:
//
//   SQLAllocHandle / SQLFreeHandle / SQLSetEnvAttr / SQLDriverConnect
//   SQLSetConnectAttr / SQLEndTran
//   SQLExecDirect / SQLNumResultCols / SQLDescribeCol / SQLFetch / SQLGetData
//   SQLBindParameter / SQLRowCount / SQLGetDiagRec / SQLGetInfo
//   SQLTables / SQLColumns / SQLPrimaryKeys / SQLForeignKeys
//
// Parameters are bound as SQL_C_CHAR with the SQL type chosen from the ORM's
// internal DataType. The driver performs the C-to-SQL conversion, which gives
// proper typed parameters on strict servers (PostgreSQL) without having to
// hand-encode IEEE-754 doubles. Binary columns stay SQL_C_BINARY. Results are
// read back typed: integers as SQL_C_SBIGINT (Int64 exact), floating point and
// text as SQL_C_CHAR, binary as SQL_C_BINARY.

use 'lib-host.fun';
use 'lib-ado-base.fun';

// ---------------------------------------------------------------
// ODBC constants (ODBC 3.x)
// ---------------------------------------------------------------
var SQL_HANDLE_ENV  = 1;
var SQL_HANDLE_DBC  = 2;
var SQL_HANDLE_STMT = 3;

var SQL_SUCCESS           = 0;
var SQL_SUCCESS_WITH_INFO = 1;
var SQL_NO_DATA           = 100;

var SQL_ATTR_ODBC_VERSION = 200;
var SQL_OV_ODBC3          = 3;

var SQL_DRIVER_NOPROMPT = 0;

var SQL_ATTR_AUTOCOMMIT = 102;
var SQL_AUTOCOMMIT_OFF  = 0;
var SQL_AUTOCOMMIT_ON   = 1;
var SQL_COMMIT          = 0;
var SQL_ROLLBACK        = 1;

var SQL_NULL_DATA = -1;
var SQL_PARAM_INPUT = 1;

var SQL_C_CHAR    = 1;
var SQL_C_BINARY  = -2;
var SQL_C_SBIGINT = -25;

var SQL_CHAR           = 1;
var SQL_WCHAR          = -8;
var SQL_WVARCHAR       = -9;
var SQL_WLONGVARCHAR   = -10;
var SQL_GUID           = -11;
var SQL_NUMERIC        = 2;
var SQL_DECIMAL        = 3;
var SQL_INTEGER        = 4;
var SQL_SMALLINT       = 5;
var SQL_FLOAT          = 6;
var SQL_REAL           = 7;
var SQL_DOUBLE         = 8;
var SQL_VARCHAR        = 12;
var SQL_LONGVARCHAR    = -1;
var SQL_BINARY         = -2;
var SQL_VARBINARY      = -3;
var SQL_LONGVARBINARY  = -4;
var SQL_BIGINT         = -5;
var SQL_TINYINT        = -6;
var SQL_BIT            = -7;
var SQL_TYPE_DATE      = 91;
var SQL_TYPE_TIME      = 92;
var SQL_TYPE_TIMESTAMP = 93;

var SQL_DRIVER_NAME           = 6;
var SQL_IDENTIFIER_QUOTE_CHAR = 29;
var SQL_CATALOG_NAME_SEPARATOR = 41;

var _ODBC_PTR = 'host'.arg().getJson(fd: true).bits div 8;
var _ODBC_API = nil;

// ---------------------------------------------------------------
// pointer / integer packing (same convention as lib-ado-unx: addresses are
// passed as real Fun string addresses, never as temporary FFI copies)
// ---------------------------------------------------------------
fun _odbcBlank(c)
  result = c = 32 or c = 9 or c = 13 or c = 10;
end fun;

fun _odbcTrim(s)
  var n = s.length();
  var b = 0;
  while b < n and _odbcBlank(s.toByte(b)) do b += 1; end do;
  var e = n;
  while e > b and _odbcBlank(s.toByte(e - 1)) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

fun _odbcU16(s, off)
  result = s.toByte(off) + s.toByte(off + 1) * 256;
end fun;

fun _odbcS16(s, off)
  var u = _odbcU16(s, off);
  if u >= 32768 then u -= 65536; end if;
  result = u;
end fun;

fun _odbcU32(s, off)
  result = s.toByte(off) + s.toByte(off + 1) * 256
         + s.toByte(off + 2) * 65536 + s.toByte(off + 3) * 16777216;
end fun;

fun _odbcI64(s, off)
  var lo = _odbcU32(s, off);
  var hi = _odbcU32(s, off + 4);
  if hi >= 2147483648 then
    result = (hi - 4294967296) * 4294967296 + lo;
  else
    result = hi * 4294967296 + lo;
  end if;
end fun;

fun _odbcPtr(s, off)
  if _ODBC_PTR = 4 then
    result = _odbcU32(s, off);
  else
    result = _odbcI64(s, off);
  end if;
end fun;

// 8-byte little-endian two's-complement buffer. Split into two 32-bit halves
// because `div` truncates toward zero, so a negative Int64 cannot be shifted
// one byte at a time.
fun _odbcI64Buf(v)
  var lo = v bit and 4294967295;
  var hi = (v - lo) div 4294967296;
  hi = hi bit and 4294967295;
  var r = '';
  for i = 0 to 3 do
    r &= (lo bit and 255).toChar();
    lo = lo div 256;
  end do;
  for i = 0 to 3 do
    r &= (hi bit and 255).toChar();
    hi = hi div 256;
  end do;
  result = r;
end fun;

// ---------------------------------------------------------------
// lazy FFI table
// ---------------------------------------------------------------
fun OdbcApi()
  if _ODBC_API <> nil then result = _ODBC_API; return; end if;
  var L = DyLib('libodbc.so.2', 'libodbc.2.dylib');
  var a = new [];
  a.alloc      = L.getapi('SQLAllocHandle',    'ipp:i');
  a.free       = L.getapi('SQLFreeHandle',     'ip:i');
  a.setenv     = L.getapi('SQLSetEnvAttr',     'pipi:i');
  a.setconn    = L.getapi('SQLSetConnectAttr', 'pipi:i');
  a.drvconnect = L.getapi('SQLDriverConnect',  'ppipipip:i');
  a.disconnect = L.getapi('SQLDisconnect',     'p:i');
  a.endtran    = L.getapi('SQLEndTran',        'ipi:i');
  a.execdirect = L.getapi('SQLExecDirect',     'ppi:i');
  a.numcols    = L.getapi('SQLNumResultCols',  'pp:i');
  a.fetch      = L.getapi('SQLFetch',          'p:i');
  a.rowcount   = L.getapi('SQLRowCount',       'pp:i');
  a.describe   = L.getapi('SQLDescribeCol',    'pipippppp:i');
  a.getdata    = L.getapi('SQLGetData',        'piiplp:i');
  a.bindparam  = L.getapi('SQLBindParameter',  'piiiiliplp:i');
  a.diag       = L.getapi('SQLGetDiagRec',     'ipipppip:i');
  a.getinfo    = L.getapi('SQLGetInfo',        'pipip:i');
  a.tables     = L.getapi('SQLTables',         'ppipipipi:i');
  a.columns    = L.getapi('SQLColumns',        'ppipipipi:i');
  a.pkeys      = L.getapi('SQLPrimaryKeys',    'ppipipi:i');
  a.fkeys      = L.getapi('SQLForeignKeys',    'ppipipipipipi:i');
  _ODBC_API = a;
  result = a;
end fun;

// ---------------------------------------------------------------
// diagnostics
// ---------------------------------------------------------------
fun OdbcDiag(a, htype, h)
  result = '';
  var state = ' '.x(8);
  var native = ' '.x(8);
  var msg = ' '.x(1024);
  var tlen = ' '.x(8);
  var i = 1;
  loop
    var rc = a.diag(htype, h, i, state.toNum(-1), native.toNum(-1),
                    msg.toNum(-1), 1023, tlen.toNum(-1));
    exit when rc <> SQL_SUCCESS and rc <> SQL_SUCCESS_WITH_INFO;
    var m = msg.substr(0, _odbcU16(tlen, 0));
    if result <> '' then result &= '; '; end if;
    result &= state.substr(0, 5) & ': ' & m;
    if i >= 8 then exit; end if;
    i += 1;
  end loop;
  if result = '' then result = 'unknown ODBC error'; end if;
end fun;

fun _odbcOk(rc)
  result = rc = SQL_SUCCESS or rc = SQL_SUCCESS_WITH_INFO;
end fun;

// ---------------------------------------------------------------
// connection
// ---------------------------------------------------------------
fun _odbcAlloc(a, htype, parent)
  var b = ' '.x(_ODBC_PTR);
  var rc = a.alloc(htype, parent, b.toNum(-1));
  if not _odbcOk(rc) then
    raise 'ODBC alloc handle: ' & OdbcDiag(a, htype, parent);
  end if;
  var h = _odbcPtr(b, 0);
  if h = 0 then raise 'ODBC alloc handle: null handle'; end if;
  result = h;
end fun;

fun _odbcInfo(a, dbc, info, maxlen)
  var b = ' '.x(maxlen);
  var l = ' '.x(4);
  var rc = a.getinfo(dbc, info, b.toNum(-1), maxlen - 1, l.toNum(-1));
  if _odbcOk(rc) then
    result = b.substr(0, _odbcU16(l, 0));
  else
    result = '';
  end if;
end fun;

fun OdbcOpen(cn)
  var a = OdbcApi();
  var env = _odbcAlloc(a, SQL_HANDLE_ENV, 0);
  var rc = a.setenv(env, SQL_ATTR_ODBC_VERSION, SQL_OV_ODBC3, 0);
  if not _odbcOk(rc) then
    var e0 = OdbcDiag(a, SQL_HANDLE_ENV, env);
    a.free(SQL_HANDLE_ENV, env);
    raise 'ODBC set env: ' & e0;
  end if;
  var dbc = _odbcAlloc(a, SQL_HANDLE_DBC, env);
  var out = ' '.x(1024);
  var ol = ' '.x(4);
  rc = a.drvconnect(dbc, 0, cn.toNum(-1), cn.length(), out.toNum(-1),
                    1023, ol.toNum(-1), SQL_DRIVER_NOPROMPT);
  if not _odbcOk(rc) then
    var e = OdbcDiag(a, SQL_HANDLE_DBC, dbc);
    a.free(SQL_HANDLE_DBC, dbc);
    a.free(SQL_HANDLE_ENV, env);
    raise 'ODBC connect failed: ' & e & ' - ' & cn;
  end if;
  // A space means "no quoting support" in ODBC, so trim before the default.
  var drv = _odbcTrim(_odbcInfo(a, dbc, SQL_DRIVER_NAME, 256));
  var quote = _odbcTrim(_odbcInfo(a, dbc, SQL_IDENTIFIER_QUOTE_CHAR, 16));
  var sep = _odbcTrim(_odbcInfo(a, dbc, SQL_CATALOG_NAME_SEPARATOR, 8));
  if quote = '' then quote = '"'; end if;
  if sep = '' then sep = '.'; end if;
  result = new [api: a, env: env, dbc: dbc, driver: drv, quote: quote, sep: sep, txn: false];
end fun;

fun OdbcClose(h)
  if h = nil then return; end if;
  var a = h.api;
  try a.disconnect(h.dbc); except end try;
  try a.free(SQL_HANDLE_DBC, h.dbc); except end try;
  try a.free(SQL_HANDLE_ENV, h.env); except end try;
end fun;

fun OdbcBegin(h)
  var a = h.api;
  var rc = a.setconn(h.dbc, SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_OFF, 0);
  if not _odbcOk(rc) then
    raise 'ODBC begin: ' & OdbcDiag(a, SQL_HANDLE_DBC, h.dbc);
  end if;
  h.txn = true;
end fun;

fun _odbcEnd(h, completion)
  var a = h.api;
  var rc = a.endtran(SQL_HANDLE_DBC, h.dbc, completion);
  if not _odbcOk(rc) then
    raise 'ODBC transaction: ' & OdbcDiag(a, SQL_HANDLE_DBC, h.dbc);
  end if;
  a.setconn(h.dbc, SQL_ATTR_AUTOCOMMIT, SQL_AUTOCOMMIT_ON, 0);
  h.txn = false;
end fun;

fun OdbcCommit(h)
  _odbcEnd(h, SQL_COMMIT);
end fun;

fun OdbcRollback(h)
  _odbcEnd(h, SQL_ROLLBACK);
end fun;

// ---------------------------------------------------------------
// statement splitting (ODBC SQLExecDirect runs one statement; the ADO/ORM
// shape "INSERT ...; SELECT last_insert_rowid()" needs two calls)
// ---------------------------------------------------------------
fun _odbcSplit(sql)
  result = new [];
  var n = sql.length();
  var start = 0;
  var i = 0;
  var q = 0;
  var line = false;
  var block = false;
  while i < n do
    var c = sql.toByte(i);
    if line then
      if c = 10 then line = false; end if;
    elsif block then
      if c = 42 and i + 1 < n and sql.toByte(i + 1) = 47 then
        block = false;
        i += 1;
      end if;
    elsif q <> 0 then
      if c = q then
        if i + 1 < n and sql.toByte(i + 1) = q then
          i += 1;
        else
          q = 0;
        end if;
      end if;
    else
      if c = 39 or c = 34 or c = 96 then
        q = c;
      elsif c = 45 and i + 1 < n and sql.toByte(i + 1) = 45 then
        line = true;
        i += 1;
      elsif c = 47 and i + 1 < n and sql.toByte(i + 1) = 42 then
        block = true;
        i += 1;
      elsif c = 59 then
        var part = sql.substr(start, i - start);
        if _odbcTrim(part) <> '' then result.@add(part); end if;
        start = i + 1;
      end if;
    end if;
    i += 1;
  end do;
  var tail = sql.substr(start);
  if _odbcTrim(tail) <> '' then result.@add(tail); end if;
end fun;

// Count '?' outside quoted strings and comments, so a literal question mark in
// SQL text is not mistaken for a parameter marker.
fun _odbcParamCount(sql)
  result = 0;
  var n = sql.length();
  var i = 0;
  var q = 0;
  var line = false;
  var block = false;
  while i < n do
    var c = sql.toByte(i);
    if line then
      if c = 10 then line = false; end if;
    elsif block then
      if c = 42 and i + 1 < n and sql.toByte(i + 1) = 47 then
        block = false;
        i += 1;
      end if;
    elsif q <> 0 then
      if c = q then
        if i + 1 < n and sql.toByte(i + 1) = q then
          i += 1;
        else
          q = 0;
        end if;
      end if;
    else
      if c = 39 or c = 34 or c = 96 then
        q = c;
      elsif c = 45 and i + 1 < n and sql.toByte(i + 1) = 45 then
        line = true;
        i += 1;
      elsif c = 47 and i + 1 < n and sql.toByte(i + 1) = 42 then
        block = true;
        i += 1;
      elsif c = 63 then
        result += 1;
      end if;
    end if;
    i += 1;
  end do;
end fun;

// ---------------------------------------------------------------
// parameter binding. ps = [{v, dt}, ...], dt is the ORM DataType 0..12.
// ---------------------------------------------------------------
fun _odbcParamType(dt)
  case dt div 1 is
    when 0  do result = SQL_SMALLINT;
    when 1  do result = SQL_INTEGER;
    when 2  do result = SQL_BIGINT;
    when 3  do result = SQL_REAL;
    when 4  do result = SQL_DOUBLE;
    when 5  do result = SQL_NUMERIC;
    when 6  do result = SQL_BIT;
    when 7  do result = SQL_VARCHAR;
    when 8  do result = SQL_VARCHAR;
    when 9  do result = SQL_VARCHAR;
    when 10 do result = SQL_LONGVARCHAR;
    when 11 do result = SQL_VARBINARY;
    when 12 do result = SQL_LONGVARBINARY;
    else result = SQL_VARCHAR;
  end case;
end fun;

fun _odbcBindOne(a, st, i, p, keep)
  var v = p.v;
  if v = nil and v.eq(nil) then
    var ind0 = _odbcI64Buf(SQL_NULL_DATA);
    keep.@add(ind0);
    var rc0 = a.bindparam(st, i, SQL_PARAM_INPUT, SQL_C_CHAR, SQL_VARCHAR,
                          1, 0, 0, 0, ind0.toNum(-1));
    if not _odbcOk(rc0) then
      raise 'ODBC bind null: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
    end if;
    return;
  end if;

  var dt = (p.dt or 0) div 1;
  var raw;
  if dt = 6 then
    if v then raw = '1'; else raw = '0'; end if;
  else
    raw = '' & v;
  end if;
  var len = raw.length();
  var buf = raw;
  if len = 0 then buf = ' '; end if; // non-null pointer for a zero-length value
  var vt = SQL_C_CHAR;
  var pt = _odbcParamType(dt);
  var dec = 0;
  if pt = SQL_NUMERIC then
    var dp = raw.subpos('.');
    if dp >= 0 then dec = raw.length() - dp - 1; end if;
  end if;
  if pt = SQL_VARBINARY or pt = SQL_LONGVARBINARY then
    vt = SQL_C_BINARY;
  end if;
  var ind = _odbcI64Buf(len);
  keep.@add(buf);
  keep.@add(ind);
  var rc = a.bindparam(st, i, SQL_PARAM_INPUT, vt, pt, len, dec,
                       buf.toNum(-1), len, ind.toNum(-1));
  if not _odbcOk(rc) then
    raise 'ODBC bind: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
  end if;
end fun;

fun _odbcBindAll(a, st, ps, keep)
  var i = 0;
  for p in ps do
    i += 1;
    _odbcBindOne(a, st, i, p, keep);
  end do;
end fun;

// ---------------------------------------------------------------
// result columns
// ---------------------------------------------------------------
fun _odbcIntType(t)
  result = t = SQL_TINYINT or t = SQL_SMALLINT or t = SQL_INTEGER
        or t = SQL_BIGINT or t = SQL_BIT;
end fun;

fun _odbcFloatType(t)
  result = t = SQL_REAL or t = SQL_FLOAT or t = SQL_DOUBLE
        or t = SQL_NUMERIC or t = SQL_DECIMAL;
end fun;

fun _odbcBinaryType(t)
  result = t = SQL_BINARY or t = SQL_VARBINARY or t = SQL_LONGVARBINARY;
end fun;

fun _odbcColInfo(a, st, i)
  var name = ' '.x(256);
  var nl = ' '.x(4);
  var dt = ' '.x(4);
  var cs = ' '.x(8);
  var dd = ' '.x(4);
  var nu = ' '.x(4);
  var rc = a.describe(st, i, name.toNum(-1), 255, nl.toNum(-1), dt.toNum(-1),
                      cs.toNum(-1), dd.toNum(-1), nu.toNum(-1));
  if not _odbcOk(rc) then
    raise 'ODBC describe column: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
  end if;
  var nm = name.substr(0, _odbcU16(nl, 0));
  if nm = '' then nm = 'col' & i; end if;
  result = new [idx: i, name: nm, type: _odbcS16(dt, 0),
                size: _odbcI64(cs, 0), scale: _odbcS16(dd, 0)];
end fun;

fun _odbcReadText(a, st, i, maxlen)
  var out = '';
  var buf = ' '.x(maxlen);
  var ind = ' '.x(8);
  loop
    var rc = a.getdata(st, i, SQL_C_CHAR, buf.toNum(-1), maxlen, ind.toNum(-1));
    if rc = SQL_NO_DATA then result = out; return; end if;
    if not _odbcOk(rc) then
      raise 'ODBC getdata: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
    end if;
    var n = _odbcI64(ind, 0);
    if n = SQL_NULL_DATA then result = nil; return; end if;
    if n > maxlen - 1 then n = maxlen - 1; end if;
    if n > 0 then out &= buf.substr(0, n); end if;
    exit when rc = SQL_SUCCESS;
  end loop;
  result = out;
end fun;

fun _odbcReadBytes(a, st, i, maxlen)
  var out = '';
  var buf = ' '.x(maxlen);
  var ind = ' '.x(8);
  loop
    var rc = a.getdata(st, i, SQL_C_BINARY, buf.toNum(-1), maxlen, ind.toNum(-1));
    if rc = SQL_NO_DATA then result = out; return; end if;
    if not _odbcOk(rc) then
      raise 'ODBC getdata: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
    end if;
    var n = _odbcI64(ind, 0);
    if n = SQL_NULL_DATA then result = nil; return; end if;
    if n > maxlen then n = maxlen; end if;
    if n > 0 then out &= buf.substr(0, n); end if;
    exit when rc = SQL_SUCCESS;
  end loop;
  result = out;
end fun;

fun _odbcCell(a, st, c)
  var t = c.type;
  if _odbcIntType(t) then
    var b = ' '.x(8);
    var ind = ' '.x(8);
    var rc = a.getdata(st, c.idx, SQL_C_SBIGINT, b.toNum(-1), 8, ind.toNum(-1));
    if rc = SQL_NO_DATA then
      result = nil;
    elsif not _odbcOk(rc) then
      raise 'ODBC getdata: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
    elsif _odbcI64(ind, 0) = SQL_NULL_DATA then
      result = nil;
    else
      result = _odbcI64(b, 0);
    end if;
  elsif _odbcFloatType(t) then
    var s = _odbcReadText(a, st, c.idx, 128);
    if s = nil then result = nil; else result = s.toNum(); end if;
  elsif _odbcBinaryType(t) then
    result = _odbcReadBytes(a, st, c.idx, 4096);
  else
    result = _odbcReadText(a, st, c.idx, 4096);
  end if;
end fun;

fun _odbcReadResult(a, st, keep)
  var nbuf = ' '.x(4);
  var rc = a.numcols(st, nbuf.toNum(-1));
  if not _odbcOk(rc) then
    raise 'ODBC column count: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
  end if;
  var ncol = _odbcU16(nbuf, 0);
  if ncol = 0 then
    var rbuf = ' '.x(8);
    rc = a.rowcount(st, rbuf.toNum(-1));
    var n = 0;
    if _odbcOk(rc) then n = _odbcI64(rbuf, 0); end if;
    if n < 0 then n = 0; end if;
    result = new [[rows: n]];
    return;
  end if;
  var cols = new [];
  for i = 1 to ncol do cols.@add(_odbcColInfo(a, st, i)); end do;
  var rows = new [];
  loop
    rc = a.fetch(st);
    exit when rc = SQL_NO_DATA;
    if not _odbcOk(rc) then
      raise 'ODBC fetch: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
    end if;
    var row = new [];
    for c in cols do row[c.name] = _odbcCell(a, st, c); end do;
    rows.@add(row);
  end loop;
  result = rows;
end fun;

fun _odbcExecOne(h, sql, ps, bind)
  var a = h.api;
  var sb = ' '.x(_ODBC_PTR);
  var rc = a.alloc(SQL_HANDLE_STMT, h.dbc, sb.toNum(-1));
  if not _odbcOk(rc) then
    raise 'ODBC alloc stmt: ' & OdbcDiag(a, SQL_HANDLE_DBC, h.dbc);
  end if;
  var st = _odbcPtr(sb, 0);
  var keep = new [];
  try
    if bind and ps?.@count?() > 0 then
      _odbcBindAll(a, st, ps, keep);
    end if;
    rc = a.execdirect(st, sql.toNum(-1), sql.length());
    if not _odbcOk(rc) then
      raise 'ODBC exec: ' & OdbcDiag(a, SQL_HANDLE_STMT, st) & '\nSQL:\n' & sql;
    end if;
    result = _odbcReadResult(a, st, keep);
  finally
    try a.free(SQL_HANDLE_STMT, st); except end try;
  end try;
end fun;

fun OdbcRun(h, sql, ps)
  result = new [];
  var parts = _odbcSplit(sql);
  if parts.@count() > 0 and ps?.@count?() > 0 then
    var nq = _odbcParamCount(parts[0]);
    if nq <> ps.@count() then
      raise 'Execute: ? count (%s) != params (%s).\nSQL:\n%s'.format(nq, ps.@count(), sql);
    end if;
  end if;
  var first = true;
  for q in parts do
    result.@add(_odbcExecOne(h, q, ps, first));
    first = false;
  end do;
end fun;

// ---------------------------------------------------------------
// schema via the ODBC catalog functions
// ---------------------------------------------------------------
fun _odbcDefaultSchema(h)
  result = 'main';
  if h.driver.lower().subpos('sqlite') < 0 then result = ''; end if;
end fun;

// SQLTables/SQLColumns return TABLE_SCHEM for schema-aware servers (Postgres,
// SQL Server) and TABLE_CAT for catalog-only ones (MySQL). Prefer the schema,
// then the catalog, then the driver default.
fun _odbcSchemaOf(r, def)
  result = r.TABLE_SCHEM or r.TABLE_CAT or def;
end fun;

fun _odbcSchemaOf2(schem, cat, def)
  result = schem or cat or def;
end fun;

fun _odbcTablesRaw(h)
  var a = h.api;
  var st = _odbcAlloc(a, SQL_HANDLE_STMT, h.dbc);
  try
    var rc = a.tables(st, 0, 0, 0, 0, 0, 0, 0, 0);
    if not _odbcOk(rc) then
      raise 'ODBC SQLTables: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
    end if;
    result = _odbcReadResult(a, st, nil);
  finally
    try a.free(SQL_HANDLE_STMT, st); except end try;
  end try;
end fun;

fun OdbcTables(h)
  var def = _odbcDefaultSchema(h);
  result = new [];
  for r in _odbcTablesRaw(h) do
    var tn = r.TABLE_NAME or '';
    if tn <> '' and tn.lower().substr(0, 7) <> 'sqlite_' then
      result.@add(new [
        TABLE_SCHEMA: _odbcSchemaOf(r, def),
        TABLE_NAME:   tn,
        TABLE_TYPE:   (r.TABLE_TYPE or 'TABLE').upper()
      ]);
    end if;
  end do;
end fun;

fun _odbcPKeysRaw(h)
  var a = h.api;
  var def = _odbcDefaultSchema(h);
  result = new [];
  for t in OdbcTables(h) do
    if t.TABLE_TYPE = 'TABLE' then
      var st = _odbcAlloc(a, SQL_HANDLE_STMT, h.dbc);
      try
        var tn = t.TABLE_NAME;
        var rc = a.pkeys(st, 0, 0, 0, 0, tn.toNum(-1), tn.length());
        if not _odbcOk(rc) then
          raise 'ODBC SQLPrimaryKeys: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
        end if;
        for r in _odbcReadResult(a, st, nil) do
          result.@add(new [
            TABLE_SCHEMA: _odbcSchemaOf(r, def),
            TABLE_NAME:   r.TABLE_NAME or tn,
            COLUMN_NAME:  r.COLUMN_NAME or '',
            PK_NAME:      r.PK_NAME or ('pk_' & tn)
          ]);
        end do;
      finally
        try a.free(SQL_HANDLE_STMT, st); except end try;
      end try;
    end if;
  end do;
end fun;

fun OdbcPKeys(h)
  result = _odbcPKeysRaw(h);
end fun;

fun OdbcColumns(h)
  var a = h.api;
  var def = _odbcDefaultSchema(h);
  var pks = new [];
  for p in _odbcPKeysRaw(h) do
    pks[(p.TABLE_SCHEMA or def) & '.' & p.TABLE_NAME & '.' & p.COLUMN_NAME] = 1;
  end do;
  result = new [];
  for t in OdbcTables(h) do
    if t.TABLE_TYPE = 'TABLE' then
      var st = _odbcAlloc(a, SQL_HANDLE_STMT, h.dbc);
      try
        var tn = t.TABLE_NAME;
        var rc = a.columns(st, 0, 0, 0, 0, tn.toNum(-1), tn.length(), 0, 0);
        if not _odbcOk(rc) then
          raise 'ODBC SQLColumns: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
        end if;
        for r in _odbcReadResult(a, st, nil) do
          var tn2 = r.TABLE_NAME or tn;
          var cn = r.COLUMN_NAME or '';
          var sch = _odbcSchemaOf(r, def);
          result.@add(new [
            TABLE_SCHEMA: sch,
            TABLE_NAME:   tn2,
            COLUMN_NAME:  cn,
            ORDINAL_POSITION: r.ORDINAL_POSITION or 0,
            DATA_TYPE:    _odbcAdoType(r.DATA_TYPE or 0),
            IS_NULLABLE:  (r.IS_NULLABLE or 'YES').upper() = 'YES',
            Column_Flags: pks[sch & '.' & tn2 & '.' & cn] and 16 or 0,
            CHARACTER_MAXIMUM_LENGTH: r.COLUMN_SIZE or 0,
            NUMBERIC_SCALE: r.DECIMAL_DIGITS or 0
          ]);
        end do;
      finally
        try a.free(SQL_HANDLE_STMT, st); except end try;
      end try;
    end if;
  end do;
end fun;

fun OdbcFKeys(h)
  var a = h.api;
  var def = _odbcDefaultSchema(h);
  result = new [];
  // unixODBC rejects an all-NULL SQLForeignKeys call (HY009), so ask per
  // foreign-key table instead of relying on the "all catalogs" form.
  for t in OdbcTables(h) do
    if t.TABLE_TYPE = 'TABLE' then
      var st = _odbcAlloc(a, SQL_HANDLE_STMT, h.dbc);
      try
        var tn = t.TABLE_NAME;
        var rc = a.fkeys(st, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                         tn.toNum(-1), tn.length());
        if not _odbcOk(rc) then
          raise 'ODBC SQLForeignKeys: ' & OdbcDiag(a, SQL_HANDLE_STMT, st);
        end if;
        for r in _odbcReadResult(a, st, nil) do
          var fk = r.FKTABLE_NAME or tn;
          var pk = r.PKTABLE_NAME or '';
          result.@add(new [
            FK_TABLE_SCHEMA: _odbcSchemaOf2(r.FKTABLE_SCHEM, r.FKTABLE_CAT, def),
            FK_TABLE_NAME:   fk,
            FK_COLUMN_NAME:  r.FKCOLUMN_NAME or '',
            PK_TABLE_SCHEMA: _odbcSchemaOf2(r.PKTABLE_SCHEM, r.PKTABLE_CAT, def),
            PK_TABLE_NAME:   pk,
            PK_COLUMN_NAME:  r.PKCOLUMN_NAME or '',
            FK_NAME:         r.FK_NAME or ('fk_' & fk & '_' & pk)
          ]);
        end do;
      finally
        try a.free(SQL_HANDLE_STMT, st); except end try;
      end try;
    end if;
  end do;
end fun;

fun _odbcAdoType(t)
  var n = t div 1;
  if n = SQL_BIT then result = 11;                       // adBoolean
  elsif n = SQL_TINYINT then result = 16;                // adTinyInt
  elsif n = SQL_SMALLINT then result = 2;                // adSmallInt
  elsif n = SQL_INTEGER then result = 3;                 // adInteger
  elsif n = SQL_BIGINT then result = 20;                 // adBigInt
  elsif n = SQL_REAL then result = 4;                    // adSingle
  elsif n = SQL_FLOAT or n = SQL_DOUBLE then result = 5;// adDouble
  elsif n = SQL_NUMERIC or n = SQL_DECIMAL then result = 131; // adNumeric
  elsif n = SQL_LONGVARCHAR then result = 201;           // adLongVarChar
  elsif n = SQL_WLONGVARCHAR then result = 201;          // adLongVarChar
  elsif n = SQL_LONGVARBINARY then result = 205;         // adLongVarBinary
  elsif n = SQL_BINARY or n = SQL_VARBINARY then
    result = 204;                                        // adVarBinary
  elsif n = SQL_GUID then result = 72;                   // adGUID
  elsif n = SQL_WCHAR or n = SQL_WVARCHAR then result = 200; // adVarChar
  elsif n = SQL_TYPE_DATE then result = 133;             // adDBDate
  elsif n = SQL_TYPE_TIME then result = 134;             // adDBTime
  elsif n = SQL_TYPE_TIMESTAMP then result = 135;        // adDBTimeStamp
  else result = 200;                                     // adVarChar
  end if;
end fun;

fun OdbcSchema(h, schema)
  if schema = adSchemaDBInfoLiterals then
    result = new [[LiteralName: 'QUOTE', LiteralValue: h.quote],
                  [LiteralName: 'SCHEMA_SEPARATOR', LiteralValue: h.sep]];
  elsif schema = adSchemaTables then
    result = OdbcTables(h);
  elsif schema = adSchemaColumns then
    result = OdbcColumns(h);
  elsif schema = adSchemaPrimaryKeys then
    result = OdbcPKeys(h);
  elsif schema = adSchemaForeignKeys then
    result = OdbcFKeys(h);
  else
    result = new [];
  end if;
end fun;
