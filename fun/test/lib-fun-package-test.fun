// End-to-end test for the package toolchain: `fun package init`, `fun run`,
// plain-script flat mode and `fun pack` manifest defaults. Only booleans are
// printed on success; a failing run adds "failed" lines, which the Windows CI
// annotation forwards.
use 'fun/lib/lib-host.fun';

var _isWin = IsWindows();
var sep    = HostSep();
var nl     = 10.toChar();
var dq     = 34.toChar();

fun q(s)
  result = dq & s & dq;
end fun;

var _getpid;
var _system;
if _isWin then
  _getpid = 'kernel32'.getapi('GetCurrentProcessId', ':i');
  _system = LibC().getapi('system', 'a:i');
else
  _getpid = LibC().getapi('getpid', ':i');
  _system = LibC().getapi('system', 's:i');
end if;
var _pid = _getpid();
var _funHome = '';   // isolated package cache for every child below

// run cmd in dir and return its exit code; output goes to logFile
fun runIn(dir, cmd, logFile)
  if _isWin then
    var crlf = 13.toChar() & nl;
    var bat  = logFile & '.bat';
    var body = '@echo off' & crlf;
    if dir <> '' then body &= 'cd /d ' & q(dir) & crlf; end if;
    if _funHome <> '' then body &= 'set "FUN_HOME=' & _funHome & '"' & crlf; end if;
    body &= cmd & ' >' & q(logFile) & ' 2>&1' & crlf;
    bat.save(body);
    result = _system(q(q(bat)));
  else
    var c = cmd;
    if _funHome <> '' then c = 'FUN_HOME=' & q(_funHome) & ' ' & c; end if;
    if dir <> '' then c = 'cd ' & q(dir) & ' && ' & c; end if;
    c &= ' >' & q(logFile) & ' 2>&1';
    result = _system(c) div 256;
  end if;
end fun;

fun yn(p)
  result = false;
  try
    var probe = p.load(cp: 0xffff);
    result = true;
  except
  end try;
end fun;

fun loadIf(p)
  result = '';
  if yn(p) then result = p.load(); end if;
end fun;

fun logTail(p)
  result = '';
  if yn(p) then
    var s = p.load().replace(nl, ' | ');
    if s.length() > 300 then s = s.substr(0, 300); end if;
    result = s;
  end if;
end fun;

fun line(s)
  result = s.replace(13.toChar(), '').replace(nl, '');
end fun;

fun commitOf(t)
  var k = t.subpos("commit: '");
  if k < 0 then result = ''; else result = t.substr(k + 9, 40); end if;
end fun;

fun fail(tag, rc, logFile)
  if rc <> 0 then
    ?. 'failed ' & tag & ': rc=' & rc;
    ?. 'failed ' & tag & ' log: ' & logTail(logFile);
  end if;
end fun;

fun absPath(p)
  result = p;
  if _isWin then
    if p.substr(1, 1) <> ':' then result = HostCurrPath() & sep & p; end if;
  else
    if p.substr(0, 1) <> '/' then result = HostCurrPath() & sep & p; end if;
  end if;
end fun;

var base  = HostTempPath('fun-package-test-' & _pid & sep);
(base & '.seed').save('x');          // save() creates the temp dir and its parents
_funHome = base & 'funhome';   // keep tidy/run/pack away from ~/.fun
var proj  = base & 'my app' & sep;   // the space also exercises argument quoting
var empty = base & 'existing' & sep;
var libp  = base & 'libonly' & sep;
var plain = base & 'plain' & sep;
var funcmd = q(absPath(0.arg()));

// init: a new directory gets the manifest and the template
var log1 = base & 'init1.log';
var rc1 = runIn(HostCurrPath(), funcmd & ' package init ' & q(proj), log1);
fail('init', rc1, log1);
?. 'init: ' & (rc1 = 0);
?. 'manifest: ' & yn(proj & 'package.fun');
?. 'template: ' & yn(proj & 'src' & sep & 'main.fun');

// fun run: the manifest bin, with the first user argument as 2.arg()
var log2 = base & 'run1.log';
var rc2 = runIn(proj, funcmd & ' run hello', log2);
fail('run', rc2, log2);
?. 'run: ' & (rc2 = 0);
var got2 = line(loadIf(log2));
?. 'run output: ' & (got2 = 'hello, hello');
if got2 <> 'hello, hello' then ?. 'failed run output: [' & got2 & ']'; end if;

// flat mode: a plain script run from the project root
var log3 = base & 'flat.log';
var rc3 = runIn(proj, funcmd & ' ' & q('src' & sep & 'main.fun') & ' flat', log3);
fail('flat', rc3, log3);
?. 'flat: ' & (rc3 = 0);
var got3 = line(loadIf(log3));
?. 'flat output: ' & (got3 = 'hello, flat');
if got3 <> 'hello, flat' then ?. 'failed flat output: [' & got3 & ']'; end if;

// an argument with a space must survive the launcher's command-line quoting
var log3b = base & 'spacearg.log';
var rc3b = runIn(proj, funcmd & ' run ' & q('two words'), log3b);
fail('space arg', rc3b, log3b);
var got3b = line(loadIf(log3b));
?. 'space arg: ' & (rc3b = 0 and got3b = 'hello, two words');
if got3b <> 'hello, two words' then ?. 'failed space arg output: [' & got3b & ']'; end if;

// a second init refuses to touch an existing manifest
var log4 = base & 'init2.log';
var rc4 = runIn(HostCurrPath(), funcmd & ' package init ' & q(proj), log4);
if rc4 = 0 then ?. 'failed init again: rc=0'; end if;
?. 'init again refused: ' & (rc4 <> 0);

// a non-empty directory gets the manifest only; existing files stay
(empty & 'keep.txt').save('keep');
var log5 = base & 'init5.log';
var rc5 = runIn(HostCurrPath(), funcmd & ' package init ' & q(empty), log5);
fail('init existing', rc5, log5);
?. 'existing manifest: ' & yn(empty & 'package.fun');
?. 'existing kept: ' & yn(empty & 'keep.txt');
?. 'existing no template: ' & (not yn(empty & 'src' & sep & 'main.fun'));

// --lib writes lib and leaves bin empty
var log6 = base & 'init6.log';
var rc6 = runIn(HostCurrPath(), funcmd & ' package init ' & q(libp) & ' --lib', log6);
fail('init lib', rc6, log6);
var m6 = loadIf(libp & 'package.fun');
?. 'lib manifest: ' & (m6.subpos("lib: 'src/lib.fun'") >= 0 and m6.subpos("bin: ''") >= 0);

// without a manifest a plain script still runs exactly as before
(plain & 'ok.fun').save("?. 'plain-ok';" & nl);
var log7 = base & 'plain.log';
var rc7 = runIn(plain, funcmd & ' ok.fun', log7);
fail('plain', rc7, log7);
?. 'plain script: ' & (rc7 = 0);
var got7 = line(loadIf(log7));
?. 'plain script output: ' & (got7 = 'plain-ok');
if got7 <> 'plain-ok' then ?. 'failed plain output: [' & got7 & ']'; end if;

// pack: the manifest supplies entry and root; the default output is main
var log8 = base & 'pack.log';
var packed = proj & 'main';
if _isWin then packed &= '.exe'; end if;
var rc8 = runIn(proj, funcmd & ' pack', log8);
fail('pack', rc8, log8);
?. 'pack defaults: ' & (rc8 = 0 and packed.size() > 0);
var log9 = base & 'packrun.log';
var rc9 = runIn('', q(packed) & ' packed', log9);
fail('pack run', rc9, log9);
?. 'pack runs: ' & (rc9 = 0);
var got9 = line(loadIf(log9));
?. 'pack output: ' & (got9 = 'hello, packed');
if got9 <> 'hello, packed' then ?. 'failed pack output: [' & got9 & ']'; end if;

// no manifest: fun run reports a missing package
var log10 = base & 'norun.log';
var rc10 = runIn(plain, funcmd & ' run', log10);
if rc10 = 0 then ?. 'failed run missing: rc=0'; end if;
?. 'run missing manifest: ' & (rc10 <> 0);

// --- dependencies: tidy, run, pack and cache reuse -----------------------
var gdep = base & 'git dep' & sep;   // the space also exercises clone/URL quoting
(gdep & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'gitdep'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: 'lib.fun'," & nl &
  "    'fun': '9.4'," & nl &
  '    dependencies: [],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(gdep & 'lib.fun').save("fun gitHello()" & nl &
  "  result = 'git-dep-ok';" & nl & 'end fun;' & nl);
var glog = base & 'git.log';
var g1 = runIn(gdep, 'git init', glog);
var g2 = runIn(gdep, 'git add .', glog);
var g3 = runIn(gdep, 'git -c user.name=test -c user.email=test@example.com commit -m init', glog);
var g4 = runIn(gdep, 'git tag v1.0.0', glog);
fail('git fixture', g1 + g2 + g3 + g4, glog);
?. 'git fixture: ' & (g1 = 0 and g2 = 0 and g3 = 0 and g4 = 0);

var pdep = base & 'pathdep' & sep;
(pdep & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'pathdep'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: 'lib.fun'," & nl &
  "    'fun': '9.4'," & nl &
  '    dependencies: [],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(pdep & 'lib.fun').save("fun pathHello()" & nl &
  "  result = 'path-dep-ok';" & nl & 'end fun;' & nl);

var gurl = 'file://' & gdep;
if _isWin then gurl = 'file:///' & gdep.replace(92.toChar(), '/'); end if;

var dproj = base & 'dep app' & sep;
var dlog = base & 'dep-init.log';
var d0 = runIn(HostCurrPath(), funcmd & ' package init ' & q(dproj), dlog);
var d1 = runIn(dproj, funcmd & ' package add gitdep ' & q(gurl) & ' --version v1.0.0', dlog);
var d2 = runIn(dproj, funcmd & ' package add pathdep ../pathdep', dlog);
fail('dep init', d0, dlog);
fail('dep add', d1 + d2, dlog);
?. 'dep deps: ' & (d0 = 0 and d1 = 0 and d2 = 0);
(dproj & 'src' & sep & 'main.fun').save("use 'gitdep.fun';" & nl &
  "use 'pathdep.fun';" & nl &
  "var out = 2.arg();" & nl &
  "var msg = gitHello() & '-' & pathHello();" & nl &
  "?. msg;" & nl &
  "if out <> '' then out.save(msg); end if;" & nl);

var tlog = base & 'dep-tidy.log';
var t1 = runIn(dproj, funcmd & ' package tidy', tlog);
fail('tidy', t1, tlog);
?. 'tidy: ' & (t1 = 0);
var dt = loadIf(dproj & 'package.fun');
?. 'resolved both: ' & (dt.subpos("'gitdep'") >= 0 and dt.subpos("commit: '") >= 0 and dt.subpos("'pathdep'") >= 0);

var rlog = base & 'dep-run.log';
var r1 = runIn(dproj, funcmd & ' run', rlog);
fail('dep run', r1, rlog);
?. 'dep run: ' & (r1 = 0);
var ro = line(loadIf(rlog));
?. 'dep run output: ' & (ro = 'git-dep-ok-path-dep-ok');
if ro <> 'git-dep-ok-path-dep-ok' then ?. 'failed dep run output: [' & ro & ']'; end if;

var flog = base & 'dep-flat.log';
var f1 = runIn(dproj, funcmd & ' ' & q('src' & sep & 'main.fun'), flog);
fail('dep flat', f1, flog);
var fo = line(loadIf(flog));
?. 'dep flat output: ' & (f1 = 0 and fo = 'git-dep-ok-path-dep-ok');
if fo <> 'git-dep-ok-path-dep-ok' then ?. 'failed dep flat output: [' & fo & ']'; end if;

var t2log = base & 'dep-tidy2.log';
var t2 = runIn(dproj, funcmd & ' package tidy', t2log);
fail('tidy2', t2, t2log);
var t2o = line(loadIf(t2log));
?. 'tidy idempotent: ' & (t2 = 0 and t2o = 'up to date');

var plog = base & 'dep-pack.log';
var p1 = runIn(dproj, funcmd & ' pack', plog);
fail('dep pack', p1, plog);
var pout = dproj & 'main';
if _isWin then pout &= '.exe'; end if;
?. 'dep pack: ' & (p1 = 0 and pout.size() > 0);

var oldHome = _funHome;
_funHome = base & 'emptyhome';
var blog = base & 'dep-bundle.log';
var bres = base & 'dep-bundle.txt';
var b1 = runIn('', q(pout) & ' ' & q(bres), blog);
var bo = line(loadIf(bres));
var bstdout = line(loadIf(blog));
_funHome = oldHome;
fail('dep bundle', b1, blog);
?. 'dep bundle: ' & (b1 = 0);
?. 'dep bundle output: ' & (bo = 'git-dep-ok-path-dep-ok');
if bo <> 'git-dep-ok-path-dep-ok' then
  ?. 'failed dep bundle output: [' & bo & ']';
  if not yn(bres) then ?. 'failed dep bundle result file missing'; end if;
end if;
?. 'dep bundle stdout: ' & (bstdout = 'git-dep-ok-path-dep-ok');
if bstdout <> 'git-dep-ok-path-dep-ok' then ?. 'failed dep bundle stdout: [' & bstdout & ']'; end if;

var d2proj = base & 'dep2 app' & sep;
var t3log = base & 'dep2.log';
var e0 = runIn(HostCurrPath(), funcmd & ' package init ' & q(d2proj), t3log);
var e1 = runIn(d2proj, funcmd & ' package add gitdep ' & q(gurl) & ' --version v1.0.0', t3log);
var e2 = runIn(d2proj, funcmd & ' package tidy', t3log);
var dt2 = loadIf(d2proj & 'package.fun');
fail('dep2', e0 + e1 + e2, t3log);
?. 'cache reuse commit: ' & (e2 = 0 and commitOf(dt) <> '' and commitOf(dt) = commitOf(dt2));

var slog = base & 'dep-stale.log';
var s0 = runIn(dproj, funcmd & ' package add gitdep ' & q(gurl) & ' --version v2.0.0', slog);
var s1 = runIn(dproj, funcmd & ' run', slog);
?. 'stale run refused: ' & (s0 = 0 and s1 <> 0);
var s2 = runIn(dproj, funcmd & ' package add gitdep ' & q(gurl) & ' --version v1.0.0', slog);
var s3 = runIn(dproj, funcmd & ' run', slog);
?. 'stale restored: ' & (s2 = 0 and s3 = 0);

var alog = base & 'dep-edit.log';
var a1 = runIn(dproj, funcmd & ' package add tmpdep ../tmpdep', alog);
var at = loadIf(dproj & 'package.fun');
var a2 = runIn(dproj, funcmd & ' package remove tmpdep', alog);
var rt = loadIf(dproj & 'package.fun');
fail('dep add/remove', a1 + a2, alog);
?. 'add dependency: ' & (a1 = 0 and at.subpos("'tmpdep'") >= 0);
?. 'remove dependency: ' & (a2 = 0 and rt.subpos("'tmpdep'") < 0);
