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

var _getAttrs;
if _isWin then _getAttrs = 'kernel32'.getapi('GetFileAttributesA', 'a:i'); end if;
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

fun quote(s)
  if _isWin then
    // MSVCRT argv rules: backslashes before a quote are doubled (and one
    // escapes the quote); trailing backslashes are doubled before the close.
    var dq = 34.toChar();
    var bs = 92.toChar();
    var out = dq;
    var n = 0;
    var i = 0;
    while i < s.length() do
      var c = s.substr(i, 1);
      if c = bs then
        n += 1;
      elsif c = dq then
        out &= bs.x(n * 2 + 1) & dq;
        n = 0;
      else
        if n > 0 then out &= bs.x(n); n = 0; end if;
        out &= c;
      end if;
      i += 1;
    end do;
    if n > 0 then out &= bs.x(n * 2); end if;
    result = out & dq;
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

fun isDir(p)
  var d = trimDir(p);
  if d = '' then result = false; return; end if;
  if _isWin then
    var a = _getAttrs(d.replace('/', 92.toChar()));
    result = a >= 0 and (a bit and 16) <> 0;   // FILE_ATTRIBUTE_DIRECTORY
  else
    var fs = (d & '/').find();
    result = fs.@count() > 0;
  end if;
end fun;

var _dNames = new [];
var _dSrc = new [];
var _dVer = new [];
var _dLibs = new [];
var _dSeen = new [];
var _rootResolved = nil;

fun resolveRun(parentDir, m, name)
  if not name.match(/^[a-z][a-z0-9_-]*$/) then
    raise "run: invalid dependency name '" & name & "'";
  end if;
  var d = nil;
  if m.dependencies <> nil then d = m.dependencies[name]; end if;
  if d = nil then raise "run: dependency '" & name & "' is not declared in " & trimDir(parentDir); end if;
  var src = d.source or '';
  var ver = d.version or '';
  if src = '' then raise "run: dependency '" & name & "' has no source"; end if;
  var git = sourceIsGit(src);
  var eff = src;
  if not git then
    eff = HostFullPath(trimDir(parentDir) & '/' & src);
    if _isWin then eff = eff.replace(92.toChar(), '/'); end if;
  end if;
  var k = _dSeen[name];
  if k <> nil then
    var ki = k - 1;
    if _dSrc[ki] <> eff or _dVer[ki] <> ver then
      raise "run: version conflict for '" & name & "'";
    end if;
    return;
  end if;
  var r = nil;
  if _rootResolved <> nil then r = _rootResolved[name]; end if;
  if r = nil then
    raise "run: package '" & name & "' is not installed; run 'fun package tidy'";
  end if;
  if (r.source or '') <> eff or (r.version or '') <> ver then
    raise "run: package '" & name & "' changed since tidy; run 'fun package tidy'";
  end if;
  var dir = eff;
  if git then
    var commit = r.commit or '';
    if commit = '' then raise "run: resolved commit for '" & name & "' is missing"; end if;
    dir = cacheDirFor(src, commit);
  end if;
  if not isDir(dir) then
    raise "run: cache for '" & name & "' is missing; run 'fun package tidy'";
  end if;
  var m2 = readPkg(dir);
  var lib = m2.lib or '';
  if lib = '' then raise "run: dependency '" & name & "' has no lib entry"; end if;
  if lib.subpos('..') >= 0 or lib.substr(0, 1) = '/' then
    raise "run: dependency '" & name & "' has an unsafe lib path";
  end if;
  var lp = trimDir(dir) & '/' & lib;
  if not exists(lp) then raise "run: dependency '" & name & "' lib not found: " & lib; end if;
  if lp.subpos("'") >= 0 then raise "run: dependency path cannot contain a quote"; end if;
  var idx = _dNames.@count();
  _dNames.@add(name);
  _dSrc.@add(eff);
  _dVer.@add(ver);
  _dLibs.@add(lp);
  _dSeen[name] = idx + 1;

  var names = depNamesOf(dir);
  var i = 0;
  while i < names.@count() do
    resolveRun(dir, m2, names[i]);
    i += 1;
  end do;
end fun;

fun buildShims()
  var home = UtilFunHome() & 'tmp';
  UtilEnsureDir(home);
  var dir = home & '/run-' & _pid;
  var n = 1;
  while isDir(dir) do
    n += 1;
    dir = home & '/run-' & _pid & '-' & n;
  end do;
  UtilEnsureDir(dir);
  var i = 0;
  while i < _dNames.@count() do
    var body = "use '" & _dLibs[i] & "';" & 10.toChar();
    (dir & '/' & _dNames[i] & '.fun').save(body);
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
  while i < _dNames.@count() do
    var p = dir & '/' & _dNames[i] & '.fun';
    if exists(p) then p.move(); end if;
    i += 1;
  end do;
  var t = trimDir(dir);
  if _isWin then t = t.replace('/', 92.toChar()); end if;
  _rmdir(t);
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
  _rootResolved = p.resolved;
  var root = HostCurrPath();
  var names = depNamesOf(root);
  var di = 0;
  while di < names.@count() do
    resolveRun(root, p, names[di]);
    di += 1;
  end do;
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
var shimDir = '';
if _dNames.@count() > 0 then
  shimDir = buildShims();
  setFunPath(shimDir);
end if;
var code = runChild(buildCmd(entry));
if shimDir <> '' then clearShims(shimDir); end if;
exitWith(code);
