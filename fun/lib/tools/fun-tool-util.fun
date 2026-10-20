// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-tool-util: host helpers shared by the package tools: environment,
// home directory, file checks, process launch and date stamp.
//
// Names are Util*-prefixed because Fun's UID chain is global; an unprefixed
// helper here would shadow a tool's own function of the same name.
use '../lib-host.fun';

var _utilWin   = IsWindows();
var _utilMac   = IsMac();
var _utilChars = 'host'.arg().getJson(fd: true).chars;
var _utilBS    = 92.toChar();

var _utilGetEnvA;
var _utilGetEnvW;
var _utilGetenv;
var _utilStrlen;
var _utilSystem;
var _utilAttrs;
var _utilOpendir;
var _utilReaddir;
var _utilClosedir;
var _utilFindFirst;
var _utilFindNext;
var _utilFindClose;
var _utilMemcpy;
var _utilRmdir;
var _utilPidFn;
if _utilWin then
  _utilGetEnvA = 'kernel32'.getapi('GetEnvironmentVariableA', 'spi:i');
  _utilGetEnvW = 'kernel32'.getapi('GetEnvironmentVariableW', 'spi:i');
  _utilSystem  = LibC().getapi('system', 'a:i');
  _utilAttrs   = 'kernel32'.getapi('GetFileAttributesA', 'a:i');
  _utilFindFirst = 'kernel32'.getapi('FindFirstFileA', 'ap:l');
  _utilFindNext  = 'kernel32'.getapi('FindNextFileA',  'ip:i');
  _utilFindClose = 'kernel32'.getapi('FindClose',      'i:i');
  _utilRmdir     = 'kernel32'.getapi('RemoveDirectoryA', 's:i');
  _utilPidFn     = 'kernel32'.getapi('GetCurrentProcessId', ':i');
else
  _utilGetenv  = LibC().getapi('getenv', 's:p');
  _utilStrlen  = LibC().getapi('strlen', 'p:i');
  _utilSystem  = LibC().getapi('system', 's:i');
  _utilOpendir = LibC().getapi('opendir', 's:p');
  if _utilMac then
    // x86_64's plain readdir is the legacy 32-bit-inode layout; arm64 ships
    // only the 64-bit variant and has no $INODE64 alias
    try
      _utilReaddir = LibC().getapi('readdir$INODE64', 'p:p');
    except
      _utilReaddir = LibC().getapi('readdir', 'p:p');
    end try;
  else
    _utilReaddir = LibC().getapi('readdir', 'p:p');
  end if;
  _utilClosedir = LibC().getapi('closedir', 'p:i');
  _utilMemcpy   = LibC().getapi('memcpy',   'ppn:p');
  _utilRmdir    = LibC().getapi('rmdir',    's:i');
  _utilPidFn    = LibC().getapi('getpid',   ':i');
end if;

fun UtilPathSep()
  if _utilWin then result = ';'; else result = ':'; end if;
end fun;

fun UtilTrimEnd(p)
  result = p;
  while result.length() > 1 do
    var c = result.substr(result.length() - 1, 1);
    if c = '/' or c = _utilBS then
      result = result.substr(0, result.length() - 1);
    else
      exit;
    end if;
  end do;
end fun;

// environment value as a string; '' when unset
fun UtilEnv(name)
  result = '';   // result persists across calls; an early return must reset it
  if _utilWin then
    var buf = 0.toChar().x(4096);
    var n;
    if _utilChars = 2 then
      n = _utilGetEnvW(name, buf, 4096);
    else
      n = _utilGetEnvA(name, buf, 4096);
    end if;
    if n > 0 then result = buf.substr(0, n); end if;
  else
    var p = _utilGetenv(name);
    if p = nil then return; end if;
    var n = _utilStrlen(p);
    var buf = ' '.x(n);
    p.move(buf.toNum(-1), n);
    result = buf.substr(0, n);
  end if;
end fun;

// FUN_HOME, else $HOME / %USERPROFILE%; no trailing separator
fun UtilHomeDir()
  var h = UtilEnv('FUN_HOME');
  if h <> '' then
    h = UtilTrimEnd(h);
    if _utilWin then h = h.replace(_utilBS, '/'); end if;
    result = h;
    return;
  end if;
  if _utilWin then h = UtilEnv('USERPROFILE');
  else h = UtilEnv('HOME'); end if;
  if h = '' then raise 'cannot find the user home; set FUN_HOME'; end if;
  h = UtilTrimEnd(h);
  if _utilWin then h = h.replace(_utilBS, '/'); end if;
  result = h & '/.fun';
end fun;

fun UtilFunHome()
  result = UtilHomeDir() & '/';
end fun;

fun UtilQuote(s)
  if _utilWin then
    // MSVCRT argv rules: backslashes before a quote are doubled (and one
    // escapes the quote); trailing backslashes are doubled before the close.
    var q = 34.toChar();
    var out = q;
    var bs = 0;
    var i = 0;
    while i < s.length() do
      var c = s.substr(i, 1);
      if c = _utilBS then
        bs += 1;
      elsif c = q then
        out &= _utilBS.x(bs * 2 + 1) & q;
        bs = 0;
      else
        if bs > 0 then out &= _utilBS.x(bs); bs = 0; end if;
        out &= c;
      end if;
      i += 1;
    end do;
    if bs > 0 then out &= _utilBS.x(bs * 2); end if;
    result = out & q;
  else
    var q = 39.toChar();
    result = q & s.replace(q, q & _utilBS & q & q) & q;
  end if;
end fun;

fun UtilExists(p)
  result = false;
  if p = '' then return; end if;
  if _utilWin then
    result = _utilAttrs(p.replace('/', _utilBS)) >= 0;
  else
    try
      result = not not p.find();
    except
      result = false;
    end try;
  end if;
end fun;

fun UtilIsDir(p)
  var d = UtilTrimEnd(p);
  if d = '' then result = false; return; end if;
  if _utilWin then
    var a = _utilAttrs(d.replace('/', _utilBS));
    result = a >= 0 and (a bit and 16) <> 0;   // FILE_ATTRIBUTE_DIRECTORY
  else
    var fs = (d & '/').find();
    result = fs.@count() > 0;
  end if;
end fun;

// NUL-terminated name inside a byte buffer, at off, at most maxLen bytes
fun UtilCStr(b, off, maxLen)
  var n = 0;
  while n < maxLen and b.toByte(off + n) <> 0 do n += 1; end do;
  result = b.substr(off, n);
end fun;

// entry names in dir; [] when dir cannot be opened
fun UtilListDir(dir)
  result = new [];
  if _utilWin then
    var pat = dir.replace('/', _utilBS);
    if pat <> '' and pat.substr(pat.length() - 1) <> _utilBS then pat &= _utilBS; end if;
    var data = 0.toChar().x(592);   // WIN32_FIND_DATAA, d_name at 44
    var h = _utilFindFirst(pat & '*', data);
    if h <= 0 then return; end if;
    var more = true;
    while more do
      var nm = UtilCStr(data, 44, 260);
      if nm <> '.' and nm <> '..' then result.@add(nm); end if;
      more = _utilFindNext(h, data) <> 0;
    end do;
    _utilFindClose(h);
  else
    var dp = _utilOpendir(dir);
    if dp = nil then return; end if;
    // struct dirent (64-bit): d_name at 21 on Darwin (d_namlen@18, d_type@20),
    // at 19 on Linux (d_type@17); d_reclen@16 on both.
    var noff = 19;
    if _utilMac then noff = 21; end if;
    var de = _utilReaddir(dp);
    while de <> 0 do
      var hd = 0.toChar().x(24);
      _utilMemcpy(hd.toNum(-1), de, 24);
      var reclen = hd.toByte(16) bit or (hd.toByte(17) << 8);
      if reclen > noff and reclen < 2048 then
        var b = 0.toChar().x(2048);
        _utilMemcpy(b.toNum(-1), de, reclen);
        var nm = UtilCStr(b, noff, reclen - noff);
        if nm <> '.' and nm <> '..' then result.@add(nm); end if;
      end if;
      de = _utilReaddir(dp);
    end do;
    _utilClosedir(dp);
  end if;
end fun;

fun UtilRmDir(p)
  var t = UtilTrimEnd(p);
  if t = '' then result = -1; return; end if;
  if _utilWin then t = t.replace('/', _utilBS); end if;
  result = _utilRmdir(t);
end fun;

fun UtilPid()
  result = _utilPidFn();
end fun;

// remove a directory tree; a missing path is a no-op
fun UtilRemoveTree(dir)
  if not UtilIsDir(dir) then return; end if;
  var names = UtilListDir(dir);
  var i = 0;
  while i < names.@count() do
    var p = UtilTrimEnd(dir) & '/' & names[i];
    if UtilIsDir(p) then UtilRemoveTree(p); else p.move(); end if;
    i += 1;
  end do;
  UtilRmDir(dir);
end fun;

// create the directory tree (save() creates parents); keeps no marker file
fun UtilEnsureDir(p)
  var d = UtilTrimEnd(p);
  if d = '' then return; end if;
  var seed = d & '/.seed';
  if not UtilExists(seed) then seed.save(''); end if;
  seed.move();
end fun;

// POSIX system() wait status (or Windows exit code) as a normal exit code
fun UtilExitCode(rc)
  if _utilWin then result = rc; return; end if;
  if rc = -1 then result = 1; return; end if;
  var sig = rc bit and 127;
  if sig = 0 then result = (rc >> 8) bit and 255; else result = 128 + sig; end if;
end fun;

// run cmd in dir, both streams to logFile; return the exit code
fun UtilRunIn(dir, cmd, logFile)
  var d = UtilTrimEnd(dir);
  if d = '' then d = dir; end if;
  if _utilWin then
    var crlf = 13.toChar() & 10.toChar();
    var bat  = logFile & '.bat';
    var body = '@echo off' & crlf;
    if d <> '' then body &= 'cd /d ' & UtilQuote(d) & crlf; end if;
    body &= cmd & ' >' & UtilQuote(logFile) & ' 2>&1' & crlf;
    bat.save(body);
    // cmd /c strips one outer quote pair; keep a plain ""pair"" (the MSVCRT
    // escaping in UtilQuote would turn the inner quotes into literals).
    result = _utilSystem('""' & bat & '""');
  else
    var c = cmd;
    if d <> '' then c = 'cd ' & UtilQuote(d) & ' && ' & c; end if;
    c &= ' >' & UtilQuote(logFile) & ' 2>&1';
    var rc = _utilSystem(c);
    result = UtilExitCode(rc);
  end if;
end fun;

