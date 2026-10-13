// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-os-unx: the common part of lib-os on Unix (Linux and macOS).
//
// The Windows lib-os.fun resolves ~40 kernel32/user32/shell32/psapi/wininet
// handles at load time and is entirely WinAPI-shaped, so it stays Windows-only.
// This module wraps the handful of functions that a normal Unix program
// actually uses, with the same names/signatures where they make sense:
//
//   paths   GetTempPath / GetCurrPath / GetFullPath      (via lib-host)
//   process exec / execShow / execWait / execWaitShow / tryExec / tryExecWait / tryFind
//   misc    SafeDelete / sleep / GetProcName / OSVersion / GetCodePage
//
// Deliberately not provided (Windows concepts): GetWinPath, GetWindowInfo,
// GetKeyState, wmi, FindbyWMI, FormatMessage, ShowLastError, waitFileChange,
// internetConnected, FindFiles, GetIPs, GetUTCBias, ClearTempPath. Calling one
// raises a clear error instead of silently returning nil.

use 'lib-host.fun';

var _usleep   = LibC().getapi('usleep',   'i:');
var _system   = LibC().getapi('system',   's:i');
var _readlink = LibC().getapi('readlink', 'spi:i');
var _uname    = LibC().getapi('uname',    'pi:i');
var _getpid   = LibC().getapi('getpid',   ':i');

// macOS has no /proc; proc_pidpath (libproc, folded into libSystem) is the
// equivalent of readlink("/proc/<pid>/exe"). Resolved only on macOS so the
// Linux load does not choke on the missing symbol.
var _procpidpath = nil;
if IsMac() then _procpidpath = LibC().getapi('proc_pidpath', 'ipi:i'); end if;

fun _cstr(buf, off)
  result = '';
  var i = off;
  while i < buf.length() and buf.toByte(i) <> 0 do
    result &= buf.toByte(i).toChar();
    i += 1;
  end do;
end fun;

fun _winonly(n)
  raise 'lib-os-unx: ' & n & ' is Windows-only';
end fun;

//==============================================================
// paths
//==============================================================
fun GetTempPath(p)
  result = HostTempPath(p or '');
end fun;

fun GetCurrPath()
  result = HostCurrPath();
end fun;

fun GetFullPath(f)
  result = HostFullPath(f);
end fun;

fun GetCodePage()
  result = 65001;   // UTF-8, the only code page that matters on Unix
end fun;

//==============================================================
// process
//
// `fn` + `ps` are pasted into a /bin/sh command line verbatim, so callers quote
// arguments themselves (there is no ShellExecute quoting on Linux).
//==============================================================
fun _shcmd(fn, ps, dir)
  var c = fn or '';
  if ps <> nil and ps <> '' then c &= ' ' & ps; end if;
  if dir <> nil and dir <> '' then c = "cd '" & dir & "' && " & c; end if;
  result = c;
end fun;

fun exec(fn, ps, dir, show, op, win)
  _system(_shcmd(fn, ps, dir) & ' &');
  result = 0;
end fun;

var execShow(fn, ps, dir) = exec(fn, ps, dir, 1);

fun execWait(fn, ps, dir, show, noWait, timeout, pid)
  var c = _shcmd(fn, ps, dir);
  if noWait then
    _system(c & ' &');
    result = 0;
  else
    result = _system(c) div 256;
  end if;
end fun;

var execWaitShow(fn, ps, dir, noWait) = execWait(fn, ps, dir, 1, noWait);
var exec@Show(fn, ps, dir) = execWaitShow(fn, ps, dir, true);
var exec@Wait(fn, ps, dir, show, timeout, getStdOut) = execWait(fn, ps, dir, show, false, timeout, nil);

fun tryFind(fn, dir)
  result = fn;
  var f = fn;
  if fn.substr(0, 1) <> '/' and fn.subpos('/') < 0 and dir <> nil and dir <> '' then
    f = dir & '/' & fn;
  end if;
  if f.size() then result = f; end if;
end fun;

fun tryExec(fn, ps, dir, show, op, win)
  result = exec(tryFind(fn, dir), ps, dir, show, op, win);
end fun;

fun tryExecWait(fn, ps, dir, show, noWait, timeout, pid)
  result = execWait(tryFind(fn, dir), ps, dir, show, noWait, timeout, pid);
end fun;

// Sleep for `ms` milliseconds (lib-os exposes the WinAPI Sleep(ms) handle).
fun sleep(ms)
  _usleep(ms * 1000);
end fun;

// Current process id (lib-os's GetPId handle).
fun GetPId()
  result = _getpid();
end fun;

// Full executable path of `pid` (like the Windows GetModuleFileNameEx result).
// `handle` is a Windows OpenProcess handle and is ignored on Unix.
fun GetProcName(pid, handle)
  result = '';
  if pid = nil then return; end if;
  var buf = ' '.x(4097);
  var n;
  if IsMac() then
    n = _procpidpath(pid, buf.toNum(-1), 4096);
  else
    n = _readlink('/proc/' & pid & '/exe', buf.toNum(-1), 4096);
  end if;
  if n > 0 then result = buf.substr(0, n); end if;
end fun;

// Kernel release string, e.g. "6.8.0-40-generic" (the Windows version returns a
// WMI number; a string is more useful here). Read from uname(2), not
// /proc/sys/kernel/osrelease, because procfs reports size 0 and `.load()` then
// reads nothing. struct utsname field width differs: 65 bytes on Linux (release
// at 130) but 256 on Darwin (release at 512), hence the host-dependent buffer
// and offset.
fun OSVersion()
  if IsMac() then
    var mb = 0.toChar().x(1280);   // 5 x 256
    if _uname(mb.toNum(-1)) <> 0 then result = '';
    else result = _cstr(mb, 512); end if;
  else
    var buf = 0.toChar().x(512);
    if _uname(buf.toNum(-1)) <> 0 then result = '';
    else result = _cstr(buf, 130); end if;
  end if;
end fun;

fun SafeDelete(f)
  var t = f & 0.random();
  f.move(t);
  t.move(); f.move();
end fun;

//==============================================================
// explicitly Windows-only
//==============================================================
fun GetWinPath()            result = _winonly('GetWinPath');            end fun;
fun GetWindowInfo(h, g)     result = _winonly('GetWindowInfo');         end fun;
fun GetKeyState(key)        result = _winonly('GetKeyState');           end fun;
fun wmi(cmd, ret, sort)     result = _winonly('wmi');                   end fun;
fun FindbyWMI(pid)          result = _winonly('FindbyWMI');             end fun;
fun FormatMessage(code)     result = _winonly('FormatMessage');         end fun;
fun ShowLastError()         result = _winonly('ShowLastError');         end fun;
fun FindFiles(path, sort)   result = _winonly('FindFiles');             end fun;
fun GetIPs()                result = _winonly('GetIPs');                end fun;
fun GetUTCBias()            result = _winonly('GetUTCBias');            end fun;
fun waitFileChange(f)       result = _winonly('waitFileChange');        end fun;
fun internetConnected()     result = _winonly('internetConnected');     end fun;
fun ClearTempPath(p, init)  result = _winonly('ClearTempPath');         end fun;
