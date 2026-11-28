// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// test: a small test registry and assertion library for `fun test`.
//
// Test files import `test.fun` and register blocks:
//   test('name', { assert.equal(1 + 1, 2); });
// Inside a body, test.skip('reason') ends the test as skipped.
// test.todo(name, body, reason) marks an expected failure; test.todo(name, reason)
// is a placeholder. Todo tests do not fail the run.
// Benchmarks: bench('name', { ... }) registers one; runBenches() calibrates
// and prints ns/op. The runner runs them only with `fun test -bench`.
// Assertions: equal, not_equal, is_true, is_false, match (regex), contains
// (substring), greater, less, is_nil, not_nil, raises, fail; each takes an
// optional trailing message.
// The runner calls `runTests()`; each test file runs in its own process.
use 'runtime.fun';

var _tests = new [];
var _current = '';
var _nl = 10.toChar();
var _inTest = false;
var _skipPending = false;
var _skipReason = '';
var _SKIP_PREFIX = '__fun_test_skip__:';

fun test(name, body)
  // Function-body array literals are singletons; allocate per test.
  var t = new [];
  t.@add(name);
  t.@add(body);
  var src = runtime.source(1);
  if src = nil then
    t.@add(nil);
    t.@add(nil);
  else
    t[4] = src['file'];
    t[5] = src['line'];
  end if;
  _tests.@add(t);
end fun;

fun _oneLine(v)
  if v.type() = 0 then result = ''; return; end if;
  result = ('' & v).replace(13.toChar() & 10.toChar(), ' ').replace(13.toChar(), ' ').replace(10.toChar(), ' ');
end fun;

fun _test_skip(reason)
  if not _inTest then
    raise 'test.skip: can only be called inside a test body';
  end if;
  var why = _oneLine(reason);
  if not _skipPending then _skipReason = why; end if;
  _skipPending = true;
  raise _SKIP_PREFIX & why;
end fun;

test.skip = _test_skip;

fun _test_todo(name, body, reason)
  // Two-argument form: a function is an expected-failure body; any other
  // second value is the placeholder reason. Three-argument form: the body
  // must be a function (or nil for a placeholder), never a silent non-call.
  if reason = nil then
    if body.type() <> 0 then
      reason = body;
      body = nil;
    end if;
  elsif body.type() <> 0 then
    raise 'test.todo: expected-failure body must be a function';
  end if;
  var why = _oneLine(reason);
  var t = new [];
  t.@add(name);
  t.@add(body);
  t.@add(true);
  t.@add(why);
  var src = runtime.source(1);
  if src <> nil then
    t[4] = src['file'];
    t[5] = src['line'];
  end if;
  _tests.@add(t);
end fun;

test.todo = _test_todo;

fun _str(v)
  result = '' & v;
end fun;

fun _compose(msg, diag)
  if msg = nil or msg = '' then
    result = diag;
  else
    result = msg & _nl & '  ' & diag;
  end if;
end fun;

fun _fail(msg)
  raise msg;
end fun;

fun assert_equal(actual, expected, msg)
  if actual <> expected then
    _fail(_compose(msg, 'expected ' & _str(expected) & ', got ' & _str(actual)));
  end if;
end fun;

fun assert_not_equal(actual, expected, msg)
  if actual = expected then
    _fail(_compose(msg, 'expected not equal, got ' & _str(actual)));
  end if;
end fun;

fun assert_true(cond, msg)
  if not cond then
    _fail(_compose(msg, 'expected true, got false'));
  end if;
end fun;

fun assert_false(cond, msg)
  if cond then
    _fail(_compose(msg, 'expected false, got true'));
  end if;
end fun;

fun assert_match(s, re, msg)
  if not (s =~ re) then
    _fail(_compose(msg, "expected a match for '" & _str(s) & "'"));
  end if;
end fun;

fun assert_contains(s, part, msg)
  if s.subpos(part) < 0 then
    _fail(_compose(msg, "expected to contain '" & _str(part) & "', got '" & _str(s) & "'"));
  end if;
end fun;

fun assert_greater(actual, limit, msg)
  if not (actual > limit) then
    _fail(_compose(msg, 'expected > ' & _str(limit) & ', got ' & _str(actual)));
  end if;
end fun;

fun assert_less(actual, limit, msg)
  if not (actual < limit) then
    _fail(_compose(msg, 'expected < ' & _str(limit) & ', got ' & _str(actual)));
  end if;
end fun;

fun assert_is_nil(v, msg)
  if v <> nil then
    _fail(_compose(msg, 'expected nil, got ' & _str(v)));
  end if;
end fun;

fun assert_not_nil(v, msg)
  if v = nil then
    _fail(_compose(msg, 'expected not nil'));
  end if;
end fun;

fun assert_raises(block, part, msg)
  var raised = false;
  var caught = '';
  try
    block();
  except
    raised = true;
    caught = _str(@);
  end try;
  if not raised then
    _fail(_compose(msg, "expected error containing '" & part & "', got: no error"));
  elsif caught.subpos(part) < 0 then
    _fail(_compose(msg, "expected error containing '" & part & "', got: '" & caught & "'"));
  end if;
end fun;

fun assert_fail(msg)
  _fail(msg);
end fun;

var assert = [
  equal: assert_equal,
  not_equal: assert_not_equal,
  is_true: assert_true,
  is_false: assert_false,
  match: assert_match,
  contains: assert_contains,
  greater: assert_greater,
  less: assert_less,
  is_nil: assert_is_nil,
  not_nil: assert_not_nil,
  raises: assert_raises,
  fail: assert_fail
];

fun runTests()
  var failed = 0;
  var skipped = 0;
  var todo = 0;
  var i = 0;
  while i < _tests.@count() do
    var t = _tests[i];
    _current = t[0];
    _skipPending = false;
    _skipReason = '';
    var isTodo = t.@count() > 2 and t[2] = true;
    var todoReason = '';
    if t.@count() > 3 then todoReason = t[3]; end if;
    var completed = false;
    var err = '';
    // Placeholder todos have no body; normal nil bodies keep the old ok behavior.
    if not (isTodo and t[1] = nil) then
      _inTest = true;
      try
        t[1]();
        completed = true;
      except
        err = _str(@);
      end try;
      _inTest = false;
    end if;
    if _skipPending then
      skipped += 1;
      var line = 'skip: ' & _current;
      if _skipReason <> '' then line &= ' (' & _skipReason & ')'; end if;
      ?. line;
    elsif isTodo then
      todo += 1;
      if completed then
        ?. 'todo passed: ' & _current & ' (remove todo)';
      else
        var todoLine = 'todo: ' & _current;
        if todoReason <> '' then todoLine &= ' (' & todoReason & ')'; end if;
        ?. todoLine;
      end if;
    elsif completed then
      ?. 'ok ' & _current;
    else
      failed += 1;
      ?. 'not ok ' & _current;
      if err <> '' then ?. '  ' & err; end if;
      var loc = '';
      var le = runtime.lastError();
      if le <> nil then
        var ef = le['file'];
        if ef <> nil and t[4] <> nil and ef = t[4] then
          loc = (le['path'] or ef) & ':' & le['line'];
        end if;
        if loc = '' then
          var st = le['stack'];
          if st <> nil and t[4] <> nil and st.@count() > 0 then
            for j = 0 to st.@count() - 1 do
              if loc = '' and st[j]['file'] = t[4] then
                loc = (st[j]['path'] or st[j]['file']) & ':' & st[j]['line'];
              end if;
            end do;
          end if;
        end if;
      end if;
      if loc <> '' then ?. '  at ' & loc; end if;
    end if;
    i += 1;
  end do;
  var total = _tests.@count();
  var summary = '# tests: ' & total & ' passed: ' & (total - failed - skipped - todo) & ' failed: ' & failed;
  if skipped > 0 or todo > 0 then summary &= ' skipped: ' & skipped; end if;
  if todo > 0 then summary &= ' todo: ' & todo; end if;
  ?. summary;
end fun;

// ---- bench --------------------------------------------------------------

var _benches = new [];

fun bench(name, body)
  // Function-body array literals are singletons; allocate per bench.
  var t = new [];
  t.@add(name);
  t.@add(body);
  _benches.@add(t);
end fun;

// One benchmark: warm up once, then double N from 10 until a round takes
// >= 1s (capped at N=10^8 or 5s total) and report ns/op from that round.
fun _runOneBench(b)
  var name = b[0];
  var body = b[1];
  var fail = '';
  try
    body();
  except
    fail = _str(@);
  end try;
  var el = 0;
  var n = 10;
  if fail = '' then
    var qpf = 1000 / -1.time();
    var totalMs = 0;
    while true do
      var t0 = -2.time();
      var i = 0;
      try
        while i < n do
          body();
          i += 1;
        end do;
      except
        fail = _str(@);
      end try;
      if fail <> '' then exit; end if;
      el = (-2.time() - t0) * qpf;
      totalMs += el;
      if el >= 1000 or n >= 100000000 or totalMs >= 5000 then exit; end if;
      n *= 10;
    end do;
  end if;
  if fail <> '' then
    ?. 'not ok bench: ' & name;
    ?. '  ' & fail;
    return 1;
  end if;
  ?. 'bench: ' & name & '  ' & n & '  ' & (el * 1000000 / n div 1) & ' ns/op';
  return 0;
end fun;

fun runBenches()
  var failed = 0;
  var i = 0;
  while i < _benches.@count() do
    failed += _runOneBench(_benches[i]);
    i += 1;
  end do;
  var summary = '# benches: ' & _benches.@count();
  if failed > 0 then summary &= ' failed: ' & failed; end if;
  ?. summary;
end fun;
