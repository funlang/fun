// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-jsbox: end-to-end tests for the Fun wrapper and the QuickJS-ng worker.
//
//   src/prj/fun/build-jsbox.sh
//   fun/funcmd fun/test/jsbox_test.fun
//
// The runner fun/test/run-jsbox-test.sh does both. If the worker is missing,
// the file reports a single skip instead of failing the whole suite.

use 'fun/lib/test.fun';
use 'fun/lib/lib-jsbox.fun' as jsb;
use 'fun/lib/fs.fun';
use 'fun/lib/lib-path.fun';
use 'fun/lib/env.fun';

fun _worker_path()
  var p = env.get('FUN_JSBOX');
  if not p.eq(nil) and not p.eq('') then result = p; return; end if;
  result = PathJoin([PathDir(0.arg()), 'fun-jsbox']);
end fun;

var _worker = _worker_path();
var _have = fs.exists(_worker);
if not _have and fs.exists('fun/fun-jsbox') then
  _worker = 'fun/fun-jsbox';
  _have = true;
end if;

if _have then
  test('jsbox: evaluate a pure function', {
    var r = jsb.run(
      'var s = 0; for (var i = 0; i < input.rows.length; i++) s += input.rows[i].n; return {sum: s};',
      [rows: [[n: 1], [n: 2], [n: 3]]],
      [timeout: 500]
    );
    assert.is_true(r.ok);
    assert.equal(r.value.sum, 6);
    assert.equal(r.engine, 'quickjs-ng');
    assert.is_true(r.usage.wall_ms >= 0);
  });

  test('jsbox: syntax error has line and column', {
    var r = jsb.run('var = ;', nil);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'syntax');
    assert.equal(r.error.line, 1);
    assert.equal(r.error.column, 5);
    assert.is_true(r.error.retryable);
  });

  test('jsbox: runtime error has message and line', {
    var code = 'var x = 1;' & 10.toChar() & 'throw new Error("boom");';
    var r = jsb.run(code, nil);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'runtime');
    assert.equal(r.error.line, 2);
    assert.contains(r.error.message, 'boom');
  });

  test('jsbox: timeout', {
    var r = jsb.run('while (true) {}', nil, [timeout: 100]);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'timeout');
  });

  test('jsbox: memory limit', {
    var r = jsb.run('var a = []; while (true) a.push(a);', nil,
                    [timeout: 2000, memory: 4 * 1024 * 1024]);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'oom');
  });

  test('jsbox: output limit', {
    var r = jsb.run('return new Array(5000).join("x");', nil,
                    [timeout: 500, output: 1024]);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'output_limit');
  });

  test('jsbox: non-JSON return value', {
    var r = jsb.run('return function () {};', nil);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'runtime');
  });

  test('jsbox: deterministic Math.random and Date.now', {
    var code = 'return [Math.random(), Math.random(), Date.now()];';
    var opts = [seed: 42, now: 1700000000000];
    var a = jsb.run(code, nil, opts);
    var b = jsb.run(code, nil, opts);
    assert.is_true(a.ok);
    assert.is_true(b.ok);
    assert.equal(a.value.@toJson(0, json: true), b.value.@toJson(0, json: true));
    assert.equal(a.value[2], 1700000000000);
  });

  test('jsbox: no host capabilities', {
    var r = jsb.run(
      'return [typeof require, typeof process, typeof console, typeof std, typeof os, typeof print];',
      nil
    );
    assert.is_true(r.ok);
    for i = 0 to 5 do assert.equal(r.value[i], 'undefined'); end do;
  });

  test('jsbox: JSON input and unicode output', {
    var r = jsb.run('return {s: "你好😀", v: input.v, n: input.n};',
                    [v: '值', n: 7]);
    assert.is_true(r.ok);
    assert.equal(r.value.s, '你好😀');
    assert.equal(r.value.v, '值');
    assert.equal(r.value.n, 7);
  });

  test('jsbox: invalid code type raises', {
    assert.raises({ jsb.run(123, nil); }, 'code must be a string');
  });
else
  test('jsbox: worker not built', {
    test.skip('run src/prj/fun/build-jsbox.sh');
  });
end if;

runTests();
