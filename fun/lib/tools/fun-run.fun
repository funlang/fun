// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-run: run a script in package context.
//
//     2.arg() = 'run'  -> entry is package.fun's bin (explicit `fun run`)
//     otherwise        -> 2.arg() is the script (a plain `fun <script>`
//                         dispatched here because the cwd has package.fun)
//
// User arguments start at 3.arg(); the interpreter dispatches this tool with
// ArgShift = -1, so the original script/subcommand keeps slot 2 and the
// child sees the same 1.arg()/2.arg() layout as a direct run.
//
// The child is started with FUN_PACKAGE_READY=1 so it does not enter package
// mode again. That variable is also the escape hatch for a broken manifest:
//     FUN_PACKAGE_READY=1 fun <script.fun>
//
// v1 runs from the manifest directory only and does not resolve dependencies
// yet (that is the tidy/cache stage); a manifest with dependencies is refused.
use '../lib-host.fun';

var _isWin = IsWindows();
var _facts = 'host'.arg().getJson(fd: true);

var _getAttrs;
if _isWin then _getAttrs = 'kernel32'.getapi('GetFileAttributesA', 'a:i'); end if;
var _system = LibC().getapi('system', 's:i');
var _putenv;
var _setEnv;
var _exit;
var _exitProcess;
if _isWin then
  _setEnv = 'kernel32'.getapi('SetEnvironmentVariableA', 'ss:i');
  _exitProcess = 'kernel32'.getapi('ExitProcess', 'i:');
else
  _putenv = LibC().getapi('putenv', 's:i');
  _exit = LibC().getapi('exit', 'i:');
end if;

fun quote(s)
  if _isWin then
    var dq = 34.toChar();
    result = dq & s & dq;
  else
    var sq = 39.toChar();
    result = sq & s.replace(sq, sq & 92.toChar() & sq & sq) & sq;
  end if;
end fun;

fun buildCmd(entry)
  var cmd = quote(0.arg()) & ' ' & quote(entry);
  var i = 3;
  while i.arg() <> '' do
    cmd &= ' ' & quote(i.arg());
    i += 1;
  end do;
  result = cmd;
end fun;

fun runChild(cmd)
  var c = cmd;
  // cmd /c strips one outer quote pair when the command line holds several;
  // the extra pair keeps "exe" "script" "arg" intact.
  if _isWin then c = '"' & c & '"'; end if;
  var rc = _system(c);
  if _isWin then
    result = rc;
  elsif rc = -1 then
    result = 1;
  else
    // POSIX system() returns the wait status: exit code in bits 8..15,
    // signal in the low 7 bits (report a signal as 128 + n).
    var sig = rc bit and 127;
    if sig = 0 then
      result = (rc >> 8) bit and 255;
    else
      result = 128 + sig;
    end if;
  end if;
end fun;

fun exitWith(code)
  if code = 0 then return; end if;
  if _isWin then _exitProcess(code); else _exit(code); end if;
end fun;

fun setReady()
  if _isWin then
    _setEnv('FUN_PACKAGE_READY', '1');
  else
    _putenv('FUN_PACKAGE_READY=1');
  end if;
end fun;

fun verAtLeast(have, need)
  if need = '' then result = true; return; end if;
  var h = have;
  var n = need;
  loop
    var hp = h.subpos('.');
    var hd = h;
    if hp >= 0 then hd = h.substr(0, hp); h = h.substr(hp + 1); else h = ''; end if;
    var np = n.subpos('.');
    var nd = n;
    if np >= 0 then nd = n.substr(0, np); n = n.substr(np + 1); else n = ''; end if;
    if hd.toNum() < nd.toNum() then result = false; return; end if;
    if hd.toNum() > nd.toNum() then result = true; return; end if;
    if n = '' then result = true; return; end if;
    if h = '' then result = false; return; end if;
  end loop;
end fun;

fun exists(p)
  result = false;
  if p = '' then return; end if;
  if _isWin then
    result = _getAttrs(p.replace('/', 92.toChar())) >= 0;
  else
    try
      result = not not p.find();
    except
      result = false;
    end try;
  end if;
end fun;

fun loadPkg()
  var mf = 'package.fun';
  if not exists(mf) then
    raise 'run: package.fun not found in ' & HostCurrPath();
  end if;
  var m = mf.compile();
  result = m.package();
end fun;

var mode = 2.arg();
if mode = '' then raise 'usage: fun run [args...]'; end if;

var p = loadPkg();
if p.name = '' then raise 'run: package.fun has no name'; end if;
if p['fun'] <> '' and not verAtLeast(_facts['fun'], p['fun']) then
  raise "run: package '" & p.name & "' needs fun " & p['fun'] &
        ' or newer (host ' & _facts['fun'] & ')';
end if;
if p.dependencies <> nil and p.dependencies.@count() > 0 then
  raise "run: package '" & p.name & "' declares dependencies; dependency support is not available yet";
end if;

var entry = '';
if mode = 'run' then
  entry = p.bin;
  if entry = '' then
    raise "run: package '" & p.name & "' has no bin entry";
  end if;
else
  entry = mode;
end if;
if not exists(entry) then raise 'run: entry not found: ' & entry; end if;

setReady();
exitWith(runChild(buildCmd(entry)));
