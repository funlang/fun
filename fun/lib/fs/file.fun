// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fs/file: binary file handles. Internal to fs.fun.
use '../lib-host.fun';
use 'backend.fun';

var _fsFOpen;
var _fsFOpenW;
var _fsFRead  = LibC().getapi('fread',  'pnnp:n');
var _fsFWrite = LibC().getapi('fwrite', 'pnnp:n');
var _fsFEof   = LibC().getapi('feof',   'p:i');
var _fsFError = LibC().getapi('ferror', 'p:i');
var _fsFFlush = LibC().getapi('fflush', 'p:i');
var _fsFClose = LibC().getapi('fclose', 'p:i');
var _fsFSeek;
var _fsFTell;

if IsWindows() then
  _fsFOpen = LibC().getapi('fopen', 'ss:p');
  if _fsChars = 2 then _fsFOpenW = LibC().getapi('_wfopen', 'ss:p'); end if;
  _fsFSeek = LibC().getapi('_fseeki64', 'pli:i');
  _fsFTell = LibC().getapi('_ftelli64', 'p:l');
else
  _fsFOpen  = LibC().getapi('fopen', 'ss:p');
  _fsFSeek  = LibC().getapi('fseeko', 'pli:i');
  _fsFTell  = LibC().getapi('ftello', 'p:l');
end if;

// byte i of a raw buffer; only needed on two-byte-char builds
fun _fsByteAt(s, i)
  result = s[i * 0.5 + 0.1];
end fun;

fun _fsIntArg(v)
  result = v.type() = 3;
end fun;

fun _fsModeArg(mode)
  if mode.type() = 0 then result = 'r'; else result = '' & mode; end if;
  result = result.replace('b', '');
end fun;

fun _fsFMode(m)
  if m = 'r' then result = 'rb';
  elsif m = 'w' then result = 'wb';
  elsif m = 'a' then result = 'ab';
  elsif m = 'r+' then result = 'r+b';
  elsif m = 'w+' then result = 'w+b';
  elsif m = 'a+' then result = 'a+b';
  else result = '';
  end if;
end fun;

fun _fsFileOpen(p, mode)
  if p = nil or p = '' then raise 'fs.open: invalid path'; end if;
  if IsWindows() and _fsBits <> 64 then raise 'fs.open: not supported on 32-bit Windows'; end if;
  if _fsChars <> 1 and not IsWindows() then raise 'fs.open: unsupported character width'; end if;
  var m = _fsModeArg(mode);
  var fm = _fsFMode(m);
  if fm = '' then raise 'fs.open: invalid mode ' & (mode or ''); end if;
  var q = _fsNative(p);
  if _fsChars = 2 and IsWindows() then result = _fsFOpenW(q, fm);
  else result = _fsFOpen(q, fm); end if;
  if result = nil then raise 'fs.open: cannot open ' & p & ' (' & (mode or '') & ')'; end if;
end fun;

class _FsFile(p, mode)
  var m = _fsModeArg(mode);
  var canRead = m = 'r' or m = 'r+' or m = 'w+' or m = 'a+';
  var canWrite = m = 'w' or m = 'a' or m = 'r+' or m = 'w+' or m = 'a+';
  var h = _fsFileOpen(p, m);

  fun _check()
    if h = nil then raise 'fs: file is closed'; end if;
  end fun;

  fun read(n)
    this._check();
    if not canRead then raise 'fs: file is not open for reading'; end if;
    if n.type() = 0 then raise 'fs: read size required'; end if;
    if not _fsIntArg(n) then raise 'fs: read size must be an integer'; end if;
    n = n or 0;
    if n < 0 then raise 'fs: read size must be >= 0'; end if;
    if n > 0x7fffffff then raise 'fs: read size too large'; end if;
    if n = 0 then result = ''; return; end if;
    var raw = 0.toChar().x(n);
    var got = _fsFRead(raw.toNum(-1), 1, n, h);
    if _fsFError(h) <> 0 then raise 'fs: read failed'; end if;
    if got = 0 then
      result = '';
      return;
    end if;
    if _fsChars = 1 then
      result = raw.substr(0, got);
    else
      result = '';
      for i = 0 to got - 1 do result &= _fsByteAt(raw, i).toChar(); end do;
    end if;
  end fun;

  fun write(data)
    this._check();
    if not canWrite then raise 'fs: file is not open for writing'; end if;
    var dt = data.type();
    if dt <> 0 and dt <> 8 then raise 'fs: write data must be a string'; end if;
    var s = '' & (data or '');
    var len = s.length();
    if len = 0 then result = 0; return; end if;
    var wrote;
    if _fsChars = 1 then
      wrote = _fsFWrite(s.toNum(-1), 1, len, h);
    else
      var buf = 0.toChar().x(len);
      for i = 0 to len - 1 do buf.fromByte(i, s.toByte(i)); end do;
      wrote = _fsFWrite(buf.toNum(-1), 1, len, h);
    end if;
    if wrote <> len then raise 'fs: write failed'; end if;
    result = wrote;
  end fun;

  fun seek(offset, whence)
    this._check();
    if not _fsIntArg(offset) then raise 'fs: seek offset must be an integer'; end if;
    if whence.type() <> 0 and not _fsIntArg(whence) then raise 'fs: invalid whence ' & whence; end if;
    whence = whence or 0;
    if whence < 0 or whence > 2 then raise 'fs: invalid whence ' & whence; end if;
    if _fsFSeek(h, offset or 0, whence) <> 0 then raise 'fs: seek failed'; end if;
    result = _fsFTell(h);
    if result < 0 then raise 'fs: tell failed'; end if;
  end fun;

  fun tell()
    this._check();
    result = _fsFTell(h);
    if result < 0 then raise 'fs: tell failed'; end if;
  end fun;

  fun eof()
    this._check();
    result = _fsFEof(h) <> 0;
  end fun;

  fun flush()
    this._check();
    if not canWrite then result = true; return; end if;
    if _fsFFlush(h) <> 0 then raise 'fs: flush failed'; end if;
    result = true;
  end fun;

  fun close()
    if h = nil then result = true; return; end if;
    var x = h;
    h = nil;
    if _fsFClose(x) <> 0 then raise 'fs: close failed'; end if;
    result = true;
  end fun;
end class;
