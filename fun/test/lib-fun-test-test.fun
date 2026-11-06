// End-to-end test for `fun test`: discovery by *_test.fun, shared helpers,
// one child per file, reserved names, a third-party alias, package/run
// integration and `fun pack` staying clear of test files. Only booleans are
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
var _funHome = '';   // isolated cache and temp dir for every child below

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

fun line(s)
  result = s.replace(13.toChar(), '').replace(nl, '');
end fun;

fun has(s, part)
  result = s.subpos(part) >= 0;
end fun;

fun countOf(s, part)
  var n = 0;
  var pos = 0;
  loop
    if pos >= s.length() then exit; end if;
    var i = s.substr(pos).subpos(part);
    if i < 0 then exit; end if;
    n += 1;
    pos += i + part.length();
  end loop;
  result = n;
end fun;

fun check(label, ok)
  ?. label & ': ' & ok;
  if not ok then ?. 'failed ' & label; end if;
end fun;

fun absPath(p)
  result = p;
  if _isWin then
    if p.substr(1, 1) <> ':' then result = HostCurrPath() & sep & p; end if;
  else
    if p.substr(0, 1) <> '/' then result = HostCurrPath() & sep & p; end if;
  end if;
end fun;

var base = HostTempPath('fun-test-test-' & _pid & sep);
(base & '.seed').save('x');
_funHome = base & 'funhome';
var funcmd = q(absPath(0.arg()));

// --- a project with a bin, a lib, a path dependency and helpers ----------
var proj = base & 'main proj' & sep;
(proj & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'tproj'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: 'src/main.fun'," & nl &
  "    lib: 'src/lib.fun'," & nl &
  '    dependencies: [' & nl &
  "      'hello': [source: 'libs/hello']" & nl &
  '    ],' & nl &
  '    // >>> generated' & nl &
  '    resolved: []' & nl &
  '    // <<< generated' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(proj & 'src' & sep & 'lib.fun').save(
  'fun libGreeting()' & nl &
  "  result = 'lib-ok';" & nl &
  'end fun;' & nl);
(proj & 'src' & sep & 'main.fun').save(
  "use 'lib.fun';" & nl &
  '?. libGreeting();' & nl);
(proj & 'src' & sep & 'b_test.fun').save(
  "use 'test.fun';" & nl &
  "use 'lib.fun';" & nl &
  "test('src test', { assert.equal(libGreeting(), 'lib-ok'); });" & nl);
(proj & 'tests' & sep & 'helpers.fun').save(
  'fun add(a, b)' & nl &
  '  result = a + b;' & nl &
  'end fun;' & nl);
(proj & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl &
  "use 'helpers.fun';" & nl &
  "use 'hello.fun';" & nl & nl &
  "test('helper add', {" & nl &
  '  assert.equal(add(1, 2), 3);' & nl &
  '});' & nl & nl &
  "test('path dependency', {" & nl &
  "  assert.equal(hello('fun'), 'hello, fun');" & nl &
  '});' & nl & nl &
  "test('raises and is_false', {" & nl &
  "  assert.raises({ assert.fail('boom inside'); }, 'boom inside');" & nl &
  '  assert.is_false(2 < 1);' & nl &
  '});' & nl & nl &
  "test('matchers', {" & nl &
  "  assert.match('hello world', /^hello/);" & nl &
  "  assert.contains('hello world', 'lo wo');" & nl &
  '  assert.greater(3, 2);' & nl &
  '  assert.less(2, 3);' & nl &
  '  assert.is_nil(nil);' & nl &
  "  assert.not_nil('x');" & nl &
  '});' & nl);
(proj & 'tests' & sep & 'nested' & sep & 'deep_test.fun').save(
  "use 'test.fun';" & nl &
  "test('deep test', { assert.is_true(2 > 1); });" & nl);
(proj & 'smoke_test.fun').save(
  "use 'test.fun';" & nl &
  "// use 'some.fun' as test; this comment must not trip the reserved check" & nl &
  "test('root test', { assert.not_equal(1, 2); });" & nl);
(proj & 'dist' & sep & 'skip_test.fun').save(
  "use 'test.fun';" & nl &
  "test('dist skipped', { assert.fail('dist was not skipped'); });" & nl);
(proj & 'libs' & sep & 'hello' & sep & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'hello'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: 'lib.fun'," & nl &
  '    dependencies: [],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(proj & 'libs' & sep & 'hello' & sep & 'lib.fun').save(
  'fun hello(who)' & nl &
  "  result = 'hello, ' & who;" & nl &
  'end fun;' & nl);
(proj & 'libs' & sep & 'hello' & sep & 'dep_test.fun').save(
  "use 'test.fun';" & nl &
  "test('dependency test', { assert.fail('path dependency was not excluded'); });" & nl);

var tlog = base & 'tidy.log';
var t1 = runIn(proj, funcmd & ' package tidy', tlog);
check('tidy', t1 = 0);

var mlog = base & 'main-test.log';
var m1 = runIn(proj, funcmd & ' test', mlog);
var mo = loadIf(mlog);
check('test exits 0', m1 = 0);
check('smoke found', has(mo, 'smoke_test.fun') and has(mo, 'PASS (1)'));
check('src test found', has(mo, 'src/b_test.fun'));
check('tests helper reuse', has(mo, 'tests/a_test.fun') and has(mo, 'PASS (4)'));
check('nested test found', has(mo, 'tests/nested/deep_test.fun'));
check('dist excluded', not has(mo, 'skip_test.fun'));
check('path dep excluded', not has(mo, 'dep_test.fun'));
check('helper not a test', not has(mo, 'helpers.fun'));
check('summary', has(mo, '4 files, 7 tests: all passed'));

// --- lib-only package (no bin) -------------------------------------------
var libp = base & 'libonly' & sep;
(libp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'libonly'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: 'lib.fun'," & nl &
  '    dependencies: [],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(libp & 'lib.fun').save('fun libOnly() result = true; end fun;' & nl);
(libp & 'tests' & sep & 'main_test.fun').save(
  "use 'test.fun';" & nl &
  "test('lib only', { assert.is_true(1 = 1); });" & nl);
var llog = base & 'libonly.log';
var l1 = runIn(libp, funcmd & ' test', llog);
check('lib-only package', l1 = 0 and has(loadIf(llog), '1 file, 1 test: all passed'));

// --- failures: custom message, assert.fail, crashed child ----------------
var failp = base & 'failing' & sep;
(failp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'failing'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: ''," & nl &
  '    dependencies: [],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(failp & 'tests' & sep & 'math_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test('passing', { assert.equal(1 + 1, 2); });" & nl & nl &
  "test('custom message', {" & nl &
  "  assert.equal(1 + 1, 3, 'math is broken');" & nl &
  '});' & nl & nl &
  "test('explicit fail', {" & nl &
  "  assert.fail('unexpected state');" & nl &
  '});' & nl & nl &
  "test('matcher failure', {" & nl &
  "  assert.match('abc', /xyz/, 'must match');" & nl &
  '});' & nl);
(failp & 'crash_test.fun').save(
  "use 'test.fun';" & nl &
  "test('never runs', { assert.equal(1, 1); });" & nl &
  "raise 'boom at load';" & nl);
var flog = base & 'failing.log';
var f1 = runIn(failp, funcmd & ' test', flog);
var fo = loadIf(flog);
check('failure exits 1', f1 = 1);
check('crash marked FAIL', has(fo, 'crash_test.fun') and has(fo, 'boom at load'));
check('custom message shown', has(fo, 'not ok custom message') and has(fo, 'math is broken'));
check('diagnostic shown', has(fo, 'expected 3, got 2'));
check('assert.fail shown', has(fo, 'not ok explicit fail') and has(fo, 'unexpected state'));
check('matcher failure shown', has(fo, 'not ok matcher failure') and has(fo, 'must match'));
check('passing test quiet', not has(fo, 'ok passing'));
check('failure summary', has(fo, '2 files, 4 tests: 1 passed, 3 failed; 1 file failed to run'));

// --- skip: a test that is intentionally not run --------------------------
var skipp = base & 'skipping' & sep;
(skipp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'skipping', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(skipp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl &
  "?. 'skip log line';" & nl & nl &
  "test('passing', { assert.equal(1, 1); });" & nl & nl &
  "test('conditional', {" & nl &
  '  var go = true;' & nl &
  "  if go then test.skip('flag on'); end if;" & nl &
  "  assert.fail('after skip');" & nl &
  '});' & nl & nl &
  "test('no reason', { test.skip(); });" & nl & nl &
  "test('multiline', { test.skip('line1' & 13.toChar() & 10.toChar() & 'line2'); });" & nl & nl &
  "test('numeric', { test.skip(0); });" & nl & nl &
  "test('swallowed', {" & nl &
  '  try' & nl &
  "    test.skip('caught');" & nl &
  '  except' & nl &
  "    ?. 'caught';" & nl &
  '  end try;' & nl &
  '});' & nl);
var sklog = base & 'skipping.log';
var sk1 = runIn(skipp, funcmd & ' test', sklog);
var sko = loadIf(sklog);
check('skip exits 0', sk1 = 0);
check('skip reason shown', has(sko, 'skip: conditional (flag on)'));
check('skip no reason', has(sko, 'skip: no reason') and not has(sko, 'skip: no reason ('));
check('skip reason normalized', has(sko, 'skip: multiline (line1 line2)'));
check('skip numeric reason', has(sko, 'skip: numeric (0)'));
check('skip swallowed', has(sko, 'skip: swallowed (caught)'));
check('plain skip log not echoed', not has(sko, 'skip log line'));
check('skip pass line', has(sko, 'PASS (6, 5 skipped)'));
check('skip summary', has(sko, '1 file, 6 tests: 1 passed, 5 skipped'));

var skmixp = base & 'skipping-mixed' & sep;
(skmixp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'skipmix', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(skmixp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test('passing', { assert.equal(1, 1); });" & nl &
  "test('skipping', { test.skip('not now'); });" & nl &
  "test('failing', { assert.fail('__fun_test_skip__: boom'); });" & nl);
var skmixlog = base & 'skipping-mixed.log';
var skm1 = runIn(skmixp, funcmd & ' test', skmixlog);
var skmo = loadIf(skmixlog);
check('mixed skip exits 1', skm1 = 1);
check('mixed skip counts', has(skmo, '1 file, 3 tests: 1 passed, 1 failed, 1 skipped'));
check('skip line shown in fail', has(skmo, 'skip: skipping (not now)') and not has(skmo, 'not ok skipping'));
check('skip line shown once', countOf(skmo, 'skip: skipping (not now)') = 1);
check('sentinel text is failure', has(skmo, 'not ok failing') and not has(skmo, 'skip: failing'));

var skoutp = base & 'skipping-outside' & sep;
(skoutp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'skipout', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(skoutp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test.skip('outside');" & nl &
  "test('a', { assert.equal(1, 1); });" & nl);
var skoutlog = base & 'skipping-outside.log';
var sout1 = runIn(skoutp, funcmd & ' test', skoutlog);
check('skip outside body', sout1 = 1 and has(loadIf(skoutlog), 'can only be called inside a test body'));

// --- todo: placeholder and expected-failure tests ------------------------
var todop = base & 'todos' & sep;
(todop & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'todos', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(todop & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test('ok', { assert.equal(1, 1); });" & nl &
  "test.todo('planned', 'not written');" & nl &
  "test.todo('bare');" & nl &
  "test.todo('known red', { assert.fail('expected'); }, 'bug 1');" & nl &
  "test.todo('fixed', { assert.equal(1, 1); }, 'should pass');" & nl &
  "test.todo('skip inside', { test.skip('caught'); }, 'todo skip');" & nl &
  "test.todo('no reason body', { assert.fail('expected'); });" & nl &
  "test.todo('numeric reason', 7);" & nl &
  "test.todo('zero reason', 0);" & nl);
var todolog = base & 'todos.log';
var td1 = runIn(todop, funcmd & ' test', todolog);
var tdo = loadIf(todolog);
check('todo exits 0', td1 = 0);
check('todo placeholder shown', has(tdo, 'todo: planned (not written)'));
check('todo bare shown', has(tdo, 'todo: bare') and not has(tdo, 'todo: bare ('));
check('todo expected failure shown', has(tdo, 'todo: known red (bug 1)'));
check('todo passed shown', has(tdo, 'todo passed: fixed (remove todo)'));
check('todo skip wins', has(tdo, 'skip: skip inside (caught)') and not has(tdo, 'todo: skip inside'));
check('todo no reason body shown', has(tdo, 'todo: no reason body') and not has(tdo, 'todo passed: no reason body'));
check('todo numeric reason shown', has(tdo, 'todo: numeric reason (7)') and not has(tdo, 'todo passed: numeric reason'));
check('todo zero reason shown', has(tdo, 'todo: zero reason (0)'));
check('todo pass line', has(tdo, 'PASS (9, 1 skipped, 7 todo)'));
check('todo summary', has(tdo, '1 file, 9 tests: 1 passed, 1 skipped, 7 todo'));

var tdmixp = base & 'todo-mixed' & sep;
(tdmixp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'todomix', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(tdmixp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test('ok', { assert.equal(1, 1); });" & nl &
  "test('fails', { assert.fail('boom'); });" & nl &
  "test.todo('known red', { assert.fail('expected'); }, 'bug 2');" & nl);
var tdmixlog = base & 'todo-mixed.log';
var tdm1 = runIn(tdmixp, funcmd & ' test', tdmixlog);
var tdmixo = loadIf(tdmixlog);
check('todo mixed exits 1', tdm1 = 1);
check('todo mixed counts', has(tdmixo, '1 file, 3 tests: 1 passed, 1 failed, 1 todo'));
check('todo mixed line shown', has(tdmixo, 'todo: known red (bug 2)') and has(tdmixo, 'not ok fails'));

var tdbadp = base & 'todo-bad-body' & sep;
(tdbadp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'todobad', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(tdbadp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test.todo('bad', 'not a function', 'reason');" & nl &
  "test('a', { assert.equal(1, 1); });" & nl);
var tdbadlog = base & 'todo-bad-body.log';
var tdbad1 = runIn(tdbadp, funcmd & ' test', tdbadlog);
check('todo bad body', tdbad1 = 1 and has(loadIf(tdbadlog), 'expected-failure body must be a function'));

var tdmultip = base & 'todo-multi' & sep;
(tdmultip & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'todomulti', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(tdmultip & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test('a', { assert.equal(1, 1); });" & nl &
  "test.todo('multi todo', 'reason');" & nl);
(tdmultip & 'tests' & sep & 'b_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "test('b', { assert.equal(2, 2); });" & nl);
var tdmultilog = base & 'todo-multi.log';
var tdmulti1 = runIn(tdmultip, funcmd & ' test', tdmultilog);
var tdmultio = loadIf(tdmultilog);
check('todo multi summary', tdmulti1 = 0 and has(tdmultio, '2 files, 3 tests: 2 passed, 1 todo'));
check('todo multi pass lines', has(tdmultio, 'PASS (2, 1 todo)') and has(tdmultio, 'PASS (1)'));

var tdfakep = base & 'todo-fake-summary' & sep;
(tdfakep & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'todofake', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(tdfakep & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl & nl &
  "?. '# tests: 1 passed: 1 failed: 9 skipped: 0 todo: 5';" & nl &
  "raise 'boom after fake summary';" & nl);
var tdfakelog = base & 'todo-fake-summary.log';
var tdfake1 = runIn(tdfakep, funcmd & ' test', tdfakelog);
var tdfakeo = loadIf(tdfakelog);
check('todo fake summary', tdfake1 = 1 and has(tdfakeo, '1 file, 0 tests: 1 file failed to run'));
check('todo fake no counts', not has(tdfakeo, 'todo: 5') and not has(tdfakeo, 'passed,'));

// --- reserved names and shadowing ----------------------------------------
var resp = base & 'reserved' & sep;
(resp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'reserved'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: ''," & nl &
  '    dependencies: [' & nl &
  "      'test': [source: 'libs/testdep']" & nl &
  '    ],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(resp & 'libs' & sep & 'testdep' & sep & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'testdep', version: '0.1.0', bin: '', lib: 'lib.fun', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(resp & 'libs' & sep & 'testdep' & sep & 'lib.fun').save('fun f() result = 1; end fun;' & nl);
(resp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl &
  "test('a', { assert.equal(1, 1); });" & nl);
var rlog = base & 'reserved.log';
var r1 = runIn(resp, funcmd & ' test', rlog);
var ro = loadIf(rlog);
check('reserved dependency key', r1 = 1 and has(ro, "dependency 'test' is reserved") and not has(ro, 'PASS ('));

var aliasp = base & 'alias' & sep;
(aliasp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'alias', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(aliasp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun' as test;" & nl &
  "test('a', { assert.equal(1, 1); });" & nl);
var alog = base & 'alias.log';
var a1 = runIn(aliasp, funcmd & ' test', alog);
var ao = loadIf(alog);
check('reserved alias', a1 = 1 and has(ao, "'as test'") and not has(ao, 'PASS ('));

var shadowp = base & 'shadow' & sep;
(shadowp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'shadow', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(shadowp & 'test.fun').save('fun shadow() result = 1; end fun;' & nl);
(shadowp & 'tests' & sep & 'a_test.fun').save(
  "use 'test.fun';" & nl &
  "test('a', { assert.equal(1, 1); });" & nl);
var shlog = base & 'shadow.log';
var s1 = runIn(shadowp, funcmd & ' test', shlog);
var so = loadIf(shlog);
check('root shadow', s1 = 1 and has(so, 'shadows the test library') and not has(so, 'PASS ('));

var shadow2p = base & 'shadow2' & sep;
(shadow2p & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'shadow2', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(shadow2p & 'tests' & sep & 'test.fun').save('fun shadow() result = 1; end fun;' & nl);
(shadow2p & 'tests' & sep & 'z_test.fun').save(
  "use 'test.fun';" & nl &
  "test('z', { assert.equal(1, 1); });" & nl);
var sh2log = base & 'shadow2.log';
var s2 = runIn(shadow2p, funcmd & ' test', sh2log);
var so2 = loadIf(sh2log);
check('test dir shadow', s2 = 1 and has(so2, 'shadows the test library') and not has(so2, 'PASS ('));

// --- a third-party test library under a non-reserved alias ---------------
var thirdp = base & 'third' & sep;
(thirdp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'third', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(thirdp & 'tests' & sep & 'third-test.fun').save(
  'fun test(name, body)' & nl &
  '  body();' & nl &
  'end fun;' & nl &
  'fun check()' & nl &
  '  result = true;' & nl &
  'end fun;' & nl);
(thirdp & 'tests' & sep & 'a_test.fun').save(
  "use 'third-test.fun' as third;" & nl &
  "use 'test.fun';" & nl & nl &
  "test('uses a third-party alias', {" & nl &
  '  assert.is_true(third.check());' & nl &
  '});' & nl & nl &
  "third.test('third-party call', { assert.equal(1, 1); });" & nl);
var tplog = base & 'third.log';
var tp1 = runIn(thirdp, funcmd & ' test', tplog);
check('third-party alias', tp1 = 0 and has(loadIf(tplog), '1 file, 1 test: all passed'));

// --- a dependency that has not been tidied -------------------------------
var untidyp = base & 'untidy' & sep;
(untidyp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'untidy'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: ''," & nl &
  "    lib: ''," & nl &
  '    dependencies: [' & nl &
  "      'hello': [source: 'libs/hello']" & nl &
  '    ],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(untidyp & 'libs' & sep & 'hello' & sep & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'hello', version: '0.1.0', bin: '', lib: 'lib.fun', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(untidyp & 'libs' & sep & 'hello' & sep & 'lib.fun').save(
  'fun hello() result = 1; end fun;' & nl);
(untidyp & 'tests' & sep & 'dep_test.fun').save(
  "use 'test.fun';" & nl &
  "use 'hello.fun';" & nl &
  "test('dep', { assert.equal(hello(), 1); });" & nl);
var ulog = base & 'untidy.log';
var u1 = runIn(untidyp, funcmd & ' test', ulog);
var uo = loadIf(ulog);
check('untidied dependency', u1 = 1 and has(uo, 'fun package tidy') and
      has(uo, '1 file, 0 tests: 1 file failed to run'));

// --- no tests, missing manifest, usage -----------------------------------
var emptytp = base & 'notests' & sep;
(emptytp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [name: ' & "'notests', version: '0.1.0', bin: '', lib: '', dependencies: [], resolved: []];" & nl &
  'end fun;' & nl);
(emptytp & 'src' & sep & 'helper.fun').save('fun helper() result = 1; end fun;' & nl);
var ntlog = base & 'notests.log';
var nt1 = runIn(emptytp, funcmd & ' test', ntlog);
check('no tests found', nt1 = 0 and line(loadIf(ntlog)) = 'no tests found');

var nopkg = base & 'nopkg' & sep;
(nopkg & '.keep').save('x');
var nplog = base & 'nopkg.log';
var np1 = runIn(nopkg, funcmd & ' test', nplog);
check('missing manifest', np1 = 1 and has(loadIf(nplog), 'package.fun not found'));

var hlog = base & 'help.log';
var h1 = runIn(proj, funcmd & ' test --help', hlog);
check('help', h1 = 0 and has(loadIf(hlog), 'usage: fun test'));

var xlog = base & 'unknown.log';
var x1 = runIn(proj, funcmd & ' test foo', xlog);
check('unknown argument', x1 = 1 and has(loadIf(xlog), 'unknown argument'));

// --- pack only follows the bin graph, so tests are never bundled ---------
var packp = base & 'pack' & sep;
(packp & 'package.fun').save(
  'fun package()' & nl &
  '  result = [' & nl &
  "    name: 'packp'," & nl &
  "    version: '0.1.0'," & nl &
  "    bin: 'src/main.fun'," & nl &
  "    lib: ''," & nl &
  '    dependencies: [],' & nl &
  '    resolved: []' & nl &
  '  ];' & nl &
  'end fun;' & nl);
(packp & 'src' & sep & 'main.fun').save("?. 'packed-ok';" & nl);
(packp & 'tests' & sep & 'broken_test.fun').save(
  "use 'test.fun';" & nl &
  'this is not fun' & nl);
var pklog = base & 'pack.log';
var pk1 = runIn(packp, funcmd & ' pack', pklog);
var packed = packp & 'main';
if _isWin then packed &= '.exe'; end if;
check('pack ignores tests', pk1 = 0);
var prlog = base & 'packrun.log';
var pr1 = runIn('', q(packed), prlog);
check('packed app runs', pr1 = 0 and line(loadIf(prlog)) = 'packed-ok');
