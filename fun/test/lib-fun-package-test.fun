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

// run cmd in dir and return its exit code; output goes to logFile
fun runIn(dir, cmd, logFile)
  if _isWin then
    var crlf = 13.toChar() & nl;
    var bat  = logFile & '.bat';
    var body = '@echo off' & crlf;
    if dir <> '' then body &= 'cd /d ' & q(dir) & crlf; end if;
    body &= cmd & ' >' & q(logFile) & ' 2>&1' & crlf;
    bat.save(body);
    result = _system(q(q(bat)));
  else
    var c = cmd;
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
