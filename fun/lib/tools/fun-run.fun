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
// Dependencies come from the manifest's resolved block (written by
// `fun package tidy`): the launcher verifies them read-only, writes temp shims
// and prepends their directory to FUN_PATH before starting the child.
use '../lib-host.fun';
use 'fun-tool-util.fun';
use 'fun-package-model.fun';

var _isWin = IsWindows();
var _facts = 'host'.arg().getJson(fd: true);

var _system = LibC().getapi('system', 's:i');
var _putenv;
var _setEnv;
var _exit;
var _exitProcess;
var _rmdir;
var _pidFn;
if _isWin then
  _setEnv = 'kernel32'.getapi('SetEnvironmentVariableA', 'ss:i');
  _exitProcess = 'kernel32'.getapi('ExitProcess', 'i:');
  _rmdir = 'kernel32'.getapi('RemoveDirectoryA', 's:i');
  _pidFn = 'kernel32'.getapi('GetCurrentProcessId', ':i');
else
  _putenv = LibC().getapi('putenv', 's:i');
  _exit = LibC().getapi('exit', 'i:');
  _rmdir = LibC().getapi('rmdir', 's:i');
  _pidFn = LibC().getapi('getpid', ':i');
end if;
var _pid = _pidFn();

fun buildCmd(entry)
  var cmd = UtilQuote(0.arg()) & ' ' & UtilQuote(entry);
  var i = 3;
  while i.arg() <> '' do
    cmd &= ' ' & UtilQuote(i.arg());
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
  result = UtilExitCode(rc);
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

fun buildShims()
  var home = UtilFunHome() & 'tmp';
  UtilEnsureDir(home);
  var dir = home & '/run-' & _pid;
  var n = 1;
  while UtilIsDir(dir) do
    n += 1;
    dir = home & '/run-' & _pid & '-' & n;
  end do;
  UtilEnsureDir(dir);
  var i = 0;
  while i < PkgResNames.@count() do
    var body = "use '" & PkgResLibs[i] & "';" & 10.toChar();
    (dir & '/' & PkgResNames[i] & '.fun').save(body);
    i += 1;
  end do;
  result = dir;
end fun;

fun setFunPath(dir)
  var old = UtilEnv('FUN_PATH');
  var fp = dir;
  if old <> '' then fp &= UtilPathSep() & old; end if;
  if _isWin then _setEnv('FUN_PATH', fp); else _putenv('FUN_PATH=' & fp); end if;
end fun;

fun clearShims(dir)
  var i = 0;
  while i < PkgResNames.@count() do
    var p = dir & '/' & PkgResNames[i] & '.fun';
    if UtilExists(p) then p.move(); end if;
    i += 1;
  end do;
  var t = trimDir(dir);
  if _isWin then t = t.replace('/', 92.toChar()); end if;
  _rmdir(t);
end fun;

fun loadPkg()
  var mf = 'package.fun';
  if not UtilExists(mf) then
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
  pkgResGraph(p, HostCurrPath(), 'run', true);
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
if not UtilExists(entry) then raise 'run: entry not found: ' & entry; end if;

setReady();
var shimDir = '';
if PkgResNames.@count() > 0 then
  shimDir = buildShims();
  setFunPath(shimDir);
end if;
var code = runChild(buildCmd(entry));
if shimDir <> '' then clearShims(shimDir); end if;
exitWith(code);
