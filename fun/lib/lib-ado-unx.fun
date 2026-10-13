// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ado-unx: the Unix backend of lib-ado -- a database connection on SQLite.
//
// The Windows lib-ado.fun is COM-shaped (ADODB.Connection/Command/Recordset, an
// ODBC provider), so it cannot be reused on Unix. Following the <name>-unx
// convention this backend exposes the same ADO class and the same contract that
// lib-orm* consume:
//
//     use 'lib-ado-unx.fun';
//     var db = ADO('mydb.sqlite');      // or ':memory:' / 'Data Source=...'
//     db.Open();
//     var rows = db.Execute('SELECT id, name FROM t WHERE id > ?', false, ps: [[v: 1, dt: 1]]);
//
// Kept contract (what lib-orm.fun / lib-orm-pro.fun / lib-ado-schema.fun use):
//   * fields: quotes ('"%s"'), dot ('.'), ps ([selectAutoId]), schema, PrintSQL,
//     dontPrintSQL;
//   * Open / Close / Closed / Commit / Rollback  (+ Begin as the transaction start);
//   * Execute(sql, rsNext, stream, from, top, tick, ps) -> a single result set as
//     a flat list of row maps for SELECT, [[rows: n]] for a statement without a
//     result, and the *next* statement's rows when rsNext is set (the ORM's
//     'INSERT ...; SELECT last_insert_rowid() AS autoId' shape);
//   * ps = [{v, dt}, ...] bound positionally to '?'; dt is the ORM internal
//     DataType (0..12), see _bindParam;
//   * OpenSchema(schema) for adSchemaTables/Columns/PrimaryKeys/ForeignKeys, with
//     the ADO column names lib-ado-schema.fun reads.
//
// Connection string: SQLite has no providers, so the string is the database file,
// ':memory:', or an ADO-ish 'Data Source=<file>' / 'DSN=<file>' / 'sqlite:<file>'.
//
// Native handles are module-level getapi variables (the lib-crypt-unx pattern).
// OUT parameters (sqlite3** / stmt**) are passed as the real address of a Fun
// string (`buf.toNum(-1)`) and read back pointer-width via _zr, because the FFI
// would otherwise hand C a temporary copy (see art/notes/library-port-plan.md).

use 'lib-host.fun';

var _lib = DyLib('libsqlite3.so.0', 'libsqlite3.dylib');
var _PTR = 'host'.arg().getJson(fd: true).bits div 8; // pointer width

var _memcpy  = LibC().getapi('memcpy', 'ppn:p');

var SQLITE_OK   = 0;
var SQLITE_ROW  = 100;
var SQLITE_DONE = 101;

var SQLITE_OPEN_READONLY  = 1;
var SQLITE_OPEN_READWRITE = 2;
var SQLITE_OPEN_CREATE    = 4;
var SQLITE_TRANSIENT      = -1; // (sqlite3_destructor_type)-1

// Never handed to C as data: only its (non-NULL) address, to bind '' text.
var _emptybuf = ' ';

var SQLITE_INTEGER = 1;
var SQLITE_FLOAT   = 2;
var SQLITE_TEXT    = 3;
var SQLITE_BLOB    = 4;
var SQLITE_NULL    = 5;

// ADO OpenSchema constants (module level, like lib-ado's adSchemaDBInfoLiterals)
var adSchemaTables         = 20;
var adSchemaColumns        = 4;
var adSchemaPrimaryKeys    = 28;
var adSchemaForeignKeys    = 27;
var adSchemaDBInfoLiterals = 31;

var _open      = _lib.getapi('sqlite3_open_v2',        'spip:i');
var _close     = _lib.getapi('sqlite3_close',          'p:i');
var _errmsg    = _lib.getapi('sqlite3_errmsg',         'p:s');
var _exec      = _lib.getapi('sqlite3_exec',           'pscpp:i');
var _prepare   = _lib.getapi('sqlite3_prepare_v2',     'ppipp:i');
var _step      = _lib.getapi('sqlite3_step',           'p:i');
var _finalize  = _lib.getapi('sqlite3_finalize',       'p:i');
var _reset     = _lib.getapi('sqlite3_reset',          'p:i');
var _colcount  = _lib.getapi('sqlite3_column_count',   'p:i');
var _colname   = _lib.getapi('sqlite3_column_name',    'pi:s');
var _coltype   = _lib.getapi('sqlite3_column_type',    'pi:i');
var _colint    = _lib.getapi('sqlite3_column_int64',   'pi:l');
var _coldbl    = _lib.getapi('sqlite3_column_double',  'pi:d');
var _coltext   = _lib.getapi('sqlite3_column_text',    'pi:s');
var _colblob   = _lib.getapi('sqlite3_column_blob',    'pi:p');
var _colbytes  = _lib.getapi('sqlite3_column_bytes',   'pi:i');
var _lastid    = _lib.getapi('sqlite3_last_insert_rowid', 'p:l');
var _changes   = _lib.getapi('sqlite3_changes',        'p:i');
var _bind_int  = _lib.getapi('sqlite3_bind_int64',     'pin:i');
var _bind_dbl  = _lib.getapi('sqlite3_bind_double',    'pid:i');
var _bind_text = _lib.getapi('sqlite3_bind_text',      'pisip:i');
// same function, but the text pointer comes in as a number: the 's' path
// passes @copy[1], which is a NULL pointer for an empty string, and
// sqlite reads a NULL pointer as SQL NULL (an empty string must stay '').
var _bind_textp = _lib.getapi('sqlite3_bind_text',     'pipip:i');
var _bind_blob = _lib.getapi('sqlite3_bind_blob',      'pipip:i');
var _bind_null = _lib.getapi('sqlite3_bind_null',      'pi:i');
var _busy      = _lib.getapi('sqlite3_busy_timeout',   'pi:i');

// ---------------------------------------------------------------
// pointer-width little-endian pack/unpack (lib-utils' int2str/str2int are
// fixed at 4 bytes and Fun's >> is 32-bit; addresses live above 4GB).
// ---------------------------------------------------------------
fun _zw(v)
  result = '';
  var u = v;
  for i = 0 to _PTR - 1 do
    result &= (u mod 256).toChar();
    u = u div 256;
  end do;
end fun;

fun _zr(s, off)
  result = 0;
  var m = 1;
  for i = 0 to _PTR - 1 do
    result += s.toByte(off + i) * m;
    m *= 256;
  end do;
end fun;

// ---------------------------------------------------------------
// low level
// ---------------------------------------------------------------
fun _trim(s)
  var n = s.length();
  var b = 0;
  while b < n and _sp(s[b + 0.5]) do b += 1; end do;
  var e = n;
  while e > b and _sp(s[e - 0.5]) do e -= 1; end do;
  result = s.substr(b, e - b);
end fun;

fun _sp(c)
  result = c = 32 or c = 9 or c = 13 or c = 10;
end fun;

// SQL NULL test. FPC's `v = nil` is true for 0 and '' too (isNull treats a zero
// number as empty), so it cannot be used to decide whether a bound value is
// NULL: binding 0/FALSE stored NULL instead of 0. `v.eq(nil)` is the
// strict test, true only for nil/unassigned. Only reached when the loose
// test already said nil, so the normal binding path is unaffected.
fun _isNull(v)
  result = v.eq(nil);
end fun;

fun _conn_str(cn)
  var s = _trim(cn or '');
  var low = s.lower();
  var k = low.subpos('datasource=');
  if k < 0 then k = low.subpos('data source='); end if;
  if k < 0 then k = low.subpos('filename='); end if;
  if k < 0 then k = low.subpos('dsn='); end if;
  if k >= 0 then
    s = s.substr(s.subpos('=') + 1);
    s = _trim(s).replace(/^["'\{\}\(\s]++/, '').replace(/["'\{\}\)\s;]++$/, '');
  elsif low.substr(0, 7) = 'sqlite:' then
    s = s.substr(7);
  end if;
  result = s;
end fun;

// ---------------------------------------------------------------
// ADO
// ---------------------------------------------------------------
class ADO(cnString, args)
  var cn = _conn_str(cnString);
  var db = nil;
  var quotes = '"%s"';
  var dot = '.';
  var schema = nil;
  var PrintSQL = nil;
  var dontPrintSQL = false;
  var ps = new [selectAutoId: 'SELECT last_insert_rowid() AS autoId'];

  fun Open()
    if db <> nil then result = true; return; end if;
    var cn2 = cn;
    if cn2 = '' then cn2 = ':memory:'; end if;
    var buf = 0.toChar().x(_PTR);
    var flags = SQLITE_OPEN_READWRITE bit or SQLITE_OPEN_CREATE;
    var rc = _open(cn2, buf.toNum(-1), flags, 0);
    var h = _zr(buf, 0);
    if rc <> SQLITE_OK or h = 0 then
      if h <> 0 then
        var m = _errmsg(h);
        _close(h);
        raise 'sqlite open failed: ' & m & ' - ' & cn;
      end if;
      raise 'sqlite open failed: rc=' & rc & ' - ' & cn;
    end if;
    db = h;
    try
      _busy(db, 5000);
    except ?. @; end try;
    result = true;
  end fun;

  fun Close()
    if db <> nil then
      try _close(db); except end try;
      db = nil;
    end if;
  end fun;

  var Closed() = db = nil;

  fun Begin()
    _execRaw('BEGIN');
  end fun;

  fun Commit()
    _execRaw('COMMIT');
  end fun;

  fun Rollback()
    _execRaw('ROLLBACK');
  end fun;

  fun _execRaw(sql)
    if Closed() then Open(); end if;
    var rc = _exec(db, sql, 0, 0, 0);
    if rc <> SQLITE_OK then raise 'sqlite: ' & _errmsg(db) & ' - ' & sql; end if;
  end fun;

  // ps = the ADO/ORM params: [{v, dt}, ...]
  fun Execute(sql, rsNext, stream, from, top, tick, ps)
    if Closed() then Open(); end if;
    var sets = _run(sql, ps);
    if sets.@count() = 0 then result = new []; return; end if;
    var rs;
    if rsNext and sets.@count() > 1 then
      rs = sets[1];
      // lib-ado attaches the first statement's affected count to the next
      // recordset's single row (the ORM reads it via r[0].rows).
      if rs.@count() = 1 then rs[0].rows = sets[0][0].rows; end if;
    else
      rs = sets[sets.@count() - 1];
    end if;
    if from > 0 or top > 0 then
      var sl = new [];
      var i = 0;
      for r in rs do
        if i >= from and (top <= 0 or sl.@count() < top) then sl.@add(r); end if;
        i += 1;
      end do;
      rs = sl;
    end if;
    if tick <> nil then ?. tick; end if;
    result = rs;
  end fun;

  fun ExecuteAndClose(sql, rsNext, ps)
    try
      result = Execute(sql, rsNext, ps: ps);
    finally
      this.Close();
    end try;
  end fun;

  // Run one or more ';'-separated statements. Returns a list of result sets:
  // a set is a list of row maps (SELECT), or [[rows: n]] (no result columns).
  fun _run(sql, ps)
    result = new [];
    var rest = _trim(sql);
    var first = true;
    loop
      if _trim(rest) = '' then return; end if;
      var base = rest.toNum(-1);
      var sbuf = 0.toChar().x(_PTR);
      var tbuf = 0.toChar().x(_PTR);
      var rc = _prepare(db, base, rest.length(), sbuf.toNum(-1), tbuf.toNum(-1));
      if rc <> SQLITE_OK then raise 'sqlite prepare: ' & _errmsg(db) & '\nSQL:\n' & rest; end if;
      var st = _zr(sbuf, 0);
      if st = 0 then return; end if; // trailing whitespace/comment
      if first and ps?.@count?() > 0 then
        _bindAll(st, ps);
      end if;
      first = false;

      var ncol = _colcount(st);
      var rows = new [];
      var rc2 = 0;
      loop
        rc2 = _step(st);
        exit when rc2 <> SQLITE_ROW;
        if ncol > 0 then
          var row = new [];
          for i = 0 to ncol - 1 do
            row[_colname(st, i)] = _colval(st, i);
          end do;
          rows.@add(row);
        end if;
      end loop;
      var aff = _changes(db);
      _finalize(st);
      if rc2 <> SQLITE_DONE then raise 'sqlite step: ' & _errmsg(db) & '\nSQL:\n' & rest; end if;

      if ncol > 0 then result.@add(rows); else result.@add(new [[rows: aff]]); end if;

      var tail = _zr(tbuf, 0);
      if tail <= base then return; end if;
      rest = rest.substr(tail - base);
    end loop;
  end fun;

  fun _bindAll(st, ps)
    var i = 0;
    for p in ps do
      i += 1;
      _bindParam(st, i, p);
    end do;
  end fun;

  // ORM internal DataType (0..12) -> sqlite bind:
  //   0,1,2 int / 3,4,5 float / 6 bool / 7,8 text / 9,10 text / 11,12 blob
  fun _bindParam(st, i, p)
    var v = p.v;
    var dt = p.dt;
    if v = nil and _isNull(v) then
      _bind_null(st, i);
      return;
    end if;
    var n = dt div 1;
    if n in [0, 1, 2] then
      _bind_int(st, i, v);
    elsif n in [3, 4, 5] then
      _bind_dbl(st, i, v);
    elsif n = 6 then
      if v and 1 then _bind_int(st, i, 1); else _bind_int(st, i, 0); end if;
    elsif n in [11, 12] then
      var b = '' & v;
      _bind_blob(st, i, b.toNum(-1), b.length(), SQLITE_TRANSIENT);
    else
      var s = '' & v;
      if s = '' then
        _bind_textp(st, i, _emptybuf.toNum(-1), 0, SQLITE_TRANSIENT);
      else
        _bind_text(st, i, s, s.length(), SQLITE_TRANSIENT);
      end if;
    end if;
  end fun;

  fun _colval(st, i)
    var t = _coltype(st, i);
    if t = SQLITE_INTEGER then
      result = _colint(st, i);
    elsif t = SQLITE_FLOAT then
      result = _coldbl(st, i);
    elsif t = SQLITE_TEXT then
      result = _coltext(st, i);
    elsif t = SQLITE_BLOB then
      var n = _colbytes(st, i);
      if n <= 0 then
        result = '';
      else
        var buf = 0.toChar().x(n);
        _memcpy(buf.toNum(-1), _colblob(st, i), n);
        result = buf;
      end if;
    else
      result = nil;
    end if;
  end fun;

  // ---------------------------------------------------------------
  // Schema (ADR-ish column names read by lib-ado-schema.fun)
  // ---------------------------------------------------------------
  fun OpenSchema(schema)
    if Closed() then Open(); end if;
    if schema = adSchemaDBInfoLiterals then
      result = new [[LiteralName: 'QUOTE', LiteralValue: '"'], [LiteralName: 'SCHEMA_SEPARATOR', LiteralValue: '.']];
    elsif schema = adSchemaTables then
      result = _adTables();
    elsif schema = adSchemaColumns then
      result = _adColumns();
    elsif schema = adSchemaPrimaryKeys then
      result = _adPKeys();
    elsif schema = adSchemaForeignKeys then
      result = _adFKeys();
    else
      result = new [];
    end if;
  end fun;

  fun Init()
    // quotes/dot are fixed for SQLite; kept for parity with lib-ado.
  end fun;

  fun _tableNames()
    result = new [];
    for r in Execute('SELECT name FROM sqlite_master WHERE type = ''table'' AND name NOT LIKE ''sqlite_%'' ORDER BY name', false) do
      result.@add(r.name);
    end do;
  end fun;

  fun _adTables()
    result = new [];
    for r in Execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name", false) do
      result.@add(new [
        TABLE_SCHEMA: 'main',
        TABLE_NAME:   r.name,
        TABLE_TYPE:   r.type = 'table' and 'TABLE' or 'VIEW'
      ]);
    end do;
  end fun;

  fun _adColumns()
    result = new [];
    for t in _tableNames() do
      for c in Execute('PRAGMA table_info("' & t & '")', false) do
        var pk = c.pk or 0;
        result.@add(new [
          TABLE_SCHEMA: 'main',
          TABLE_NAME:   t,
          COLUMN_NAME:  c.name,
          ORDINAL_POSITION: (c.cid or 0) + 1,
          DATA_TYPE:    _adoType(c.type or ''),
          IS_NULLABLE:  (c.notnull or 0) = 0,
          Column_Flags: pk > 0 and 16 or 0,
          CHARACTER_MAXIMUM_LENGTH: _charLen(c.type or ''),
          NUMBERIC_SCALE: 0
        ]);
      end do;
    end do;
  end fun;

  fun _adPKeys()
    result = new [];
    for t in _tableNames() do
      for c in Execute('PRAGMA table_info("' & t & '")', false) do
        if (c.pk or 0) > 0 then
          result.@add(new [
            TABLE_SCHEMA: 'main',
            TABLE_NAME:   t,
            COLUMN_NAME:  c.name,
            PK_NAME:      'pk_' & t
          ]);
        end if;
      end do;
    end do;
  end fun;

  fun _adFKeys()
    result = new [];
    for t in _tableNames() do
      // PRAGMA foreign_key_list columns are id, seq, table, from, to, ...
      // 'from'/'table'/'to' are reserved words in Fun, so read them by string
      // subscript (member-dot syntax f.from would not parse). This SQLite
      // predates the table-valued pragma functions, so no SQL-side aliasing.
      for f in Execute('PRAGMA foreign_key_list("' & t & '")', false) do
        result.@add(new [
          FK_TABLE_SCHEMA: 'main',
          FK_TABLE_NAME:   t,
          FK_COLUMN_NAME:  f['from'],
          PK_TABLE_SCHEMA: 'main',
          PK_TABLE_NAME:   f['table'],
          PK_COLUMN_NAME:  f['to'],
          FK_NAME:         'fk_' & t & '_' & (f.id or 0)
        ]);
      end do;
    end do;
  end fun;

  // declared type -> ADO DataTypeEnum (lib-ado-schema maps these to ORM dt)
  fun _adoType(decl)
    var t = _trim(decl).upper();
    var p = t.subpos('(');
    if p >= 0 then t = t.substr(0, p); end if;
    if t = '' then result = 200; return; end if;
    if t.subpos('BIGINT') >= 0 then result = 20;       // adBigInt
    elsif t.subpos('SMALLINT') >= 0 then result = 2;   // adSmallInt
    elsif t.subpos('TINYINT') >= 0 then result = 16;   // adTinyInt
    elsif t.subpos('INT') >= 0 then result = 3;        // adInteger
    elsif t.subpos('BOOL') >= 0 then result = 11;      // adBoolean
    elsif t.subpos('DATE') >= 0 or t.subpos('TIME') >= 0 then result = 135; // adDBTimeStamp
    elsif t.subpos('DEC') >= 0 or t.subpos('NUM') >= 0 or t.subpos('MONEY') >= 0 then result = 131; // adNumeric
    elsif t.subpos('DOUB') >= 0 or t.subpos('REAL') >= 0 or t.subpos('FLOA') >= 0 then result = 5; // adDouble
    elsif t.subpos('BLOB') >= 0 or t.subpos('BINARY') >= 0 then result = 204; // adVarBinary
    else result = 200; // adVarChar
    end if;
  end fun;

  fun _charLen(decl)
    var t = decl;
    var a = t.subpos('(');
    if a < 0 then result = 0; return; end if;
    var b = t.subpos(')');
    if b < 0 then b = t.length(); end if;
    var n = _trim(t.substr(a + 1, b - a - 1));
    if n.subpos(',') >= 0 then n = n.substr(0, n.subpos(',')); end if;
    result = n.toNum() or 0;
  end fun;
end class;
