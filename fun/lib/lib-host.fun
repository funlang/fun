// Copyright (c) 2010-2026 Zhang WeiDong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-host: portable host services (path / env / process).
//
// Why a separate module instead of lib-os: lib-os resolves ~40 Windows
// handles unconditionally at load time, so it cannot even be loaded on Linux.
// Anything that only needs a couple of host services should depend on this
// module instead, so it stays loadable on every host.
//
// Platform dispatch follows the three rules validated in
// fun/test/lib-os-dispatch-prototype.fun (see art/notes/library-port-plan.md):
//   1. detect the host once, at load time, from 'host'.arg();
//   2. resolve native handles only on the host that owns them;
//   3. keep one public name/signature and put the host branch inside.
//
// Names are Host*-prefixed on purpose: lib-os already exports GetCurrPath /
// GetTempPath / GetFullPath, and two modules exporting the same name would
// shadow each other in Fun's UID chain.
//
// Linux note: an OUT buffer must be passed as the Fun string's real address
// (buf.toNum(-1)), not as an 's'/'p' string argument - the engine would hand C
// a pointer to a temporary copy and the writes would be lost. (Same on macOS.)
//
// Built-in methods used here (see also lib-cmdline-lnx.fun):
########################################
#   built-in (2)
########################################
#     n.arg()                   # argv[n]: 0 = executable, 1 = script
#     'host'.arg()              # host facts (FD): fun, os, cpu, compiler, bits, chars, version
########################################
#     'defaultCodePage'.set(cp) # default ANSI code page (e.g. 936); OleStr path only
########################################

var _hostFacts  = 'host'.arg().getJson(fd: true);
var _hostOs     = _hostFacts.os;
var _isWindows  = _hostOs = 'windows';
var _isLinux    = _hostOs = 'linux';
var _isMac      = _hostOs = 'macos';
var _isUnix     = _isLinux or _isMac;   // both POSIX, share the libc branch
var _hostSep    = '/';
var _hostChars  = _hostFacts.chars;

fun IsWindows()
  result = _isWindows;
end fun;

fun IsLinux()
  result = _isLinux;
end fun;

fun IsMac()
  result = _isMac;
end fun;

// Linux or macOS: the POSIX branch (no Windows handles, '/' separator).
fun IsUnix()
  result = _isUnix;
end fun;

//--------------------------------------------------------------
// native library names (for getapi)
//
// The *-unx backends differ from their Windows counterparts mostly in the
// library they dlopen, so the two host-dependent strings are resolved here
// once. Callers pass both spellings explicitly: Apple's compat libraries keep
// their version inside the name (libz.1.dylib, libcurl.4.dylib,
// libxml2.2.dylib) instead of after '.so' as on Linux, so a single
// (base, soname) pair cannot express both.
//--------------------------------------------------------------

// The C library: glibc's stable runtime soname on Linux; macOS folds libc
// (and much else) into libSystem; the Windows counterpart is msvcrt, which is
// what the FPC/win64 build and MinGW both link against by default. Only the
// Unix callers use it today, but the name is honest on every host.
fun LibC()
  if _isWindows then result = 'msvcrt.dll';
  elsif _isMac then result = 'libSystem.B.dylib';
  else result = 'libc.so.6'; end if;
end fun;

// One shared-object name per host.
fun DyLib(lnx, mac)
  if _isMac then result = mac; else result = lnx; end if;
end fun;

// One shared-object name per host, Windows included. The *-unx backends only
// need (Linux, macOS) because their Windows counterparts live in different
// modules, but a helper that is built on all three hosts - the FFI test
// library - needs all three spellings.
fun DyLibWin(lnx, mac, win)
  if _isWindows then result = win; elsif _isMac then result = mac; else result = lnx; end if;
end fun;

// A candidate list per host (e.g. several libcrypto versions to probe).
fun DyLibList(lnx, mac)
  if _isMac then result = mac; else result = lnx; end if;
end fun;

// Path separator of the running host.
fun HostSep()
  result = _hostSep;
end fun;

//--------------------------------------------------------------
// native handles, resolved per host
//--------------------------------------------------------------
var _HOST_MAX_PATH = 260;

var _hostGetCurrPath;   // Windows: kernel32.GetCurrentDirectory
var _hostGetTempPath;   // Windows: kernel32.GetTempPath
var _hostGetFullPath;   // Windows: kernel32.GetFullPathName
var _hostGetCmdLine;    // Windows: kernel32.GetCommandLine
var _hostGetCwd;        // Unix: LibC().getcwd
var _hostGetenv;        // Unix: LibC().getenv
var _hostSetenv;        // Unix: LibC().setenv
var _hostUnsetenv;      // Unix: LibC().unsetenv
var _hostStrlen;        // Unix: LibC().strlen
var _hostGetEnvA;       // Windows: GetEnvironmentVariableA
var _hostGetEnvW;       // Windows: GetEnvironmentVariableW
var _hostSetEnvA;       // Windows: SetEnvironmentVariableA
var _hostSetEnvW;       // Windows: SetEnvironmentVariableW
var _hostGetLastError;  // Windows: GetLastError
var _hostSetLastError;  // Windows: SetLastError

if _isUnix then
  _hostGetCwd  = LibC().getapi('getcwd',  'pi:p');
  _hostGetenv  = LibC().getapi('getenv',  's:p');
  _hostSetenv  = LibC().getapi('setenv',  'ssi:i');
  _hostUnsetenv = LibC().getapi('unsetenv', 's:i');
  _hostStrlen  = LibC().getapi('strlen',  'p:i');
else
  _hostSep = '\';
  _hostGetCmdLine  = 'kernel32'.getapi('GetCommandLine',       ':s');
  _hostGetCurrPath = 'kernel32'.getapi('GetCurrentDirectory', 'ip:i');
  _hostGetTempPath = 'kernel32'.getapi('GetTempPath',         'ip:i');
  _hostGetFullPath = 'kernel32'.getapi('GetFullPathName',     'sipp:i');
  _hostGetEnvA     = 'kernel32'.getapi('GetEnvironmentVariableA', 'spi:i');
  _hostGetEnvW     = 'kernel32'.getapi('GetEnvironmentVariableW', 'spi:i');
  _hostSetEnvA     = 'kernel32'.getapi('SetEnvironmentVariableA', 'ss:i');
  _hostSetEnvW     = 'kernel32'.getapi('SetEnvironmentVariableW', 'ss:i');
  _hostGetLastError = 'kernel32'.getapi('GetLastError', ':i');
  _hostSetLastError = 'kernel32'.getapi('SetLastError', 'i:');
end if;

//--------------------------------------------------------------
// command line
//
// Windows returns the raw process command line. Linux has no such string, so
// it is rebuilt from argv and quoted the Windows way (wrap in double quotes,
// double any inner quote) - that way the existing lib-param/lib-cmdline
// tokenizer keeps working unchanged on both hosts.
//--------------------------------------------------------------
fun HostCommandLine()
  if _isUnix then
    result = '';
    var i = 0;
    while i.arg() <> '' do
      var a = i.arg();
      var dq = 34.toChar();
      if a.subpos(' ') >= 0 or a.subpos(dq) >= 0 then
        a = '"' & a.replace(dq, dq & dq) & '"';
      end if;
      if result <> '' then result &= ' '; end if;
      result &= a;
      i += 1;
    end do;
  else
    result = _hostGetCmdLine();
  end if;
end fun;

//--------------------------------------------------------------
// current directory
//--------------------------------------------------------------
fun HostCurrPath()
  if _isUnix then
    var buf = ' '.x(4097);
    var p = _hostGetCwd(buf.toNum(-1), 4096);
    if p = nil then
      result = '';
    else
      result = buf.substr(len: _hostStrlen(buf.toNum(-1)));
    end if;
  else
    result = ' '.x(_HOST_MAX_PATH + 1);
    var ln = _hostGetCurrPath(_HOST_MAX_PATH, result);
    result = result.substr(len: ln);
  end if;
end fun;

//--------------------------------------------------------------
// temp directory, with a trailing separator, then 'extra' appended
// (same contract as lib-os.GetTempPath)
//--------------------------------------------------------------
fun HostTempPath(extra)
  if _isUnix then
    var t = _hostGetenv('TMPDIR');
    if t = nil then
      result = '/tmp/';
    else
      var ln  = _hostStrlen(t);
      var buf = ' '.x(ln + 1);
      t.move(buf.toNum(-1), ln);
      result = buf.substr(len: ln).replace(%[/]++$%, '') & '/';
    end if;
    result &= extra;
  else
    result = ' '.x(_HOST_MAX_PATH + 1);
    var ln = _hostGetTempPath(_HOST_MAX_PATH, result);
    result = result.substr(len: ln) & extra;
  end if;
end fun;

//--------------------------------------------------------------
// absolute path. Unlike libc realpath() this is purely lexical, so it also
// works for paths that do not exist yet (matching GetFullPathName's contract).
//--------------------------------------------------------------
fun HostFullPath(f)
  if _isUnix then
    var s = f;
    if s = '' then
      result = HostCurrPath();
      return;
    end if;
    if s.substr(0, 1) <> '/' then
      s = HostCurrPath() & '/' & s;
    end if;
    // segment scan, no regex dependency: collapse '' / '.' and resolve '..'
    var kept = new [];
    var cur  = '';
    var i    = 0;
    while i <= s.length() do
      var ch = s.substr(i, 1);
      if ch = '/' or i = s.length() then
        if cur = '..' then
          if kept.@count() > 0 then kept.@count(-1); end if;
        elsif cur <> '' and cur <> '.' then
          kept.@add(cur);
        end if;
        cur = '';
      else
        cur &= ch;
      end if;
      i += 1;
    end do;
    result = '';
    for p in kept do
      result = result & '/' & p;
    end do;
    if result = '' then result = '/'; end if;
  else
    result = ' '.x(_HOST_MAX_PATH + 1);
    var r = '';
    var ln = _hostGetFullPath(f, _HOST_MAX_PATH, result, r);
    result = result.substr(len: ln);
  end if;
end fun;

//--------------------------------------------------------------
// environment
//--------------------------------------------------------------
fun _hostEnvNameOk(name)
  if name = nil or name = '' then result = false; return; end if;
  if name.subpos('=') >= 0 or name.subpos(0.toChar()) >= 0 then
    result = false;
    return;
  end if;
  result = true;
end fun;

fun HostEnvHas(name)
  if not _hostEnvNameOk(name) then result = false; return; end if;
  if _isUnix then
    result = _hostGetenv(name) <> nil;
  else
    // GetEnvironmentVariable returns 0 for both "not found" and "empty".
    // Reset LastError first, then ERROR_ENVVAR_NOT_FOUND (203) means absent.
    _hostSetLastError(0);
    var buf = ' '.x(2);
    var n;
    if _hostChars = 2 then
      n = _hostGetEnvW(name, buf.toNum(-1), 2);
    else
      n = _hostGetEnvA(name, buf.toNum(-1), 2);
    end if;
    if n > 0 then result = true; return; end if;
    result = _hostGetLastError() <> 203;
  end if;
end fun;

fun HostEnvGet(name)
  if not HostEnvHas(name) then result = nil; return; end if;
  if _isUnix then
    var p = _hostGetenv(name);
    var n = _hostStrlen(p);
    if n = 0 then result = ''; return; end if;
    var buf = ' '.x(n);
    p.move(buf.toNum(-1), n);
    result = buf.substr(0, n);
  else
    var buf = ' '.x(32768);
    var n;
    if _hostChars = 2 then
      n = _hostGetEnvW(name, buf.toNum(-1), 32768);
    else
      n = _hostGetEnvA(name, buf.toNum(-1), 32768);
    end if;
    result = buf.substr(0, n);
  end if;
end fun;

fun HostEnvSet(name, value)
  if not _hostEnvNameOk(name) then result = false; return; end if;
  var v = '';
  if value <> nil then v = '' & value; end if;
  if _isUnix then
    // FFI cannot pass an empty Fun string as a C string pointer.
    var cv = v;
    if cv = '' then cv = 0.toChar().x(1); end if;
    result = _hostSetenv(name, cv, 1) = 0;
  elsif _hostChars = 2 then
    var wv = v;
    if wv = '' then wv = 0.toChar().x(2); end if;
    result = _hostSetEnvW(name, wv) <> 0;
  else
    var av = v;
    if av = '' then av = 0.toChar().x(1); end if;
    result = _hostSetEnvA(name, av) <> 0;
  end if;
end fun;

fun HostEnvUnset(name)
  if not _hostEnvNameOk(name) then result = false; return; end if;
  if _isUnix then
    result = _hostUnsetenv(name) = 0;
  elsif _hostChars = 2 then
    result = _hostSetEnvW(name, nil) <> 0;
  else
    result = _hostSetEnvA(name, nil) <> 0;
  end if;
end fun;
