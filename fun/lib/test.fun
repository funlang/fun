// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// test: a small test registry and assertion library for `fun test`.
//
// Test files import `test.fun` and register blocks:
//   test('name', { assert.equal(1 + 1, 2); });
// The runner calls `runTests()`; each test file runs in its own process.
var _tests = new [];
var _current = '';
var _nl = 10.toChar();

fun test(name, body)
  // Function-body array literals are singletons; allocate per test.
  var t = new [];
  t.@add(name);
  t.@add(body);
  _tests.@add(t);
end fun;

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
  raises: assert_raises,
  fail: assert_fail
];

fun runTests()
  var failed = 0;
  var i = 0;
  while i < _tests.@count() do
    var t = _tests[i];
    _current = t[0];
    try
      t[1]();
      ?. 'ok ' & _current;
    except
      failed += 1;
      ?. 'not ok ' & _current;
      var m = _str(@);
      if m <> '' then ?. '  ' & m; end if;
    end try;
    i += 1;
  end do;
  ?. '# tests: ' & _tests.@count() & ' passed: ' & (_tests.@count() - failed) & ' failed: ' & failed;
end fun;
