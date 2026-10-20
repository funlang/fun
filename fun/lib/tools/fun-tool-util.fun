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
var _utilChars = 'host'.arg().getJson(fd: true).chars;
var _utilBS    = 92.toChar();

var _utilGetEnvA;
var _utilGetEnvW;
var _utilGetenv;
var _utilStrlen;
var _utilSystem;
var _utilAttrs;
if _utilWin then
  _utilGetEnvA = 'kernel32'.getapi('GetEnvironmentVariableA', 'spi:i');
  _utilGetEnvW = 'kernel32'.getapi('GetEnvironmentVariableW', 'spi:i');
  _utilSystem  = LibC().getapi('system', 'a:i');
  _utilAttrs   = 'kernel32'.getapi('GetFileAttributesA', 'a:i');
else
  _utilGetenv  = LibC().getapi('getenv', 's:p');
  _utilStrlen  = LibC().getapi('strlen', 'p:i');
  _utilSystem  = LibC().getapi('system', 's:i');
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

// create the directory tree (save() creates parents); keeps no marker file
fun UtilEnsureDir(p)
  var d = UtilTrimEnd(p);
  if d = '' then return; end if;
  var seed = d & '/.seed';
  if not UtilExists(seed) then seed.save(''); end if;
  seed.move();
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
    if rc = -1 then
      result = 1;
    else
      var sig = rc bit and 127;
      if sig = 0 then result = (rc >> 8) bit and 255; else result = 128 + sig; end if;
    end if;
  end if;
end fun;

