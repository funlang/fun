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
use 'fun/lib/jsonschema.fun';

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
    assert.equal(r.error.line, 0);
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
      'return [typeof require, typeof process, typeof console, typeof std, typeof os, ' &
      'typeof print, typeof load, typeof gc, typeof setTimeout, typeof WebAssembly];',
      nil
    );
    assert.is_true(r.ok);
    for i = 0 to 9 do assert.equal(r.value[i], 'undefined'); end do;
  });

  test('jsbox: eval and Function stay inside the sandbox', {
    var r = jsb.run(
      'return [eval("typeof require"), new Function("return typeof process")()];',
      nil
    );
    assert.is_true(r.ok);
    assert.equal(r.value[0], 'undefined');
    assert.equal(r.value[1], 'undefined');
  });

  test('jsbox: JSON input and unicode output', {
    var r = jsb.run('return {s: "你好😀", v: input.v, n: input.n};',
                    [v: '值', n: 7]);
    assert.is_true(r.ok);
    assert.equal(r.value.s, '你好😀');
    assert.equal(r.value.v, '值');
    assert.equal(r.value.n, 7);
  });

  test('jsbox: modern JavaScript syntax', {
    var r = jsb.run(
      'const f = (x) => `v=${x}`;' &
      'class A { constructor() { this.x = 1; } }' &
      'return [f(2), new A().x];',
      nil
    );
    assert.is_true(r.ok);
    assert.equal(r.value[0], 'v=2');
    assert.equal(r.value[1], 1);
  });

  test('jsbox: JS result can be schema-validated', {
    var r = jsb.run(
      'var total = 0;' &
      'for (var i = 0; i < input.rows.length; i++) total += input.rows[i].amount;' &
      'return {total: total, count: input.rows.length};',
      [rows: [[amount: 10], [amount: 20]]]
    );
    assert.is_true(r.ok);
    var schema = '{"type":"object","required":["total","count"],' &
      '"properties":{"total":{"type":"integer","minimum":0},' &
      '"count":{"type":"integer","minimum":0}}}';
    assert.is_true(JsonSchema.valid(r.value, schema));

    var bad = jsb.run('return {total: "oops", count: 1};', nil);
    assert.is_true(bad.ok);
    assert.is_false(JsonSchema.valid(bad.value, schema));
  });

  test('jsbox: one-shot process isolation', {
    var a = jsb.run('Object.prototype.x = 1; globalThis.y = 2; return 1;', nil);
    assert.is_true(a.ok);
    var b = jsb.run('return [({}).x, globalThis.y];', nil);
    assert.is_true(b.ok);
    assert.is_nil(b.value[0]);
    assert.is_nil(b.value[1]);
  });

  test('jsbox: falsy JSON results are preserved', {
    var z = jsb.run('return 0', nil);
    assert.is_true(z.ok);
    assert.equal(z.value, 0);
    var f = jsb.run('return false', nil);
    assert.is_true(f.ok);
    assert.is_false(f.value);
    var s = jsb.run('return ""', nil);
    assert.is_true(s.ok);
    assert.equal(s.value, '');
    var n = jsb.run('return null', nil);
    assert.is_true(n.ok);
    assert.is_nil(n.value);
  });

  test('jsbox: falsy JSON inputs are preserved', {
    var n = jsb.run('return input', nil);
    assert.is_true(n.ok);
    assert.is_nil(n.value);
    var f = jsb.run('return input', false);
    assert.is_true(f.ok);
    assert.is_false(f.value);
    var z = jsb.run('return input', 0);
    assert.is_true(z.ok);
    assert.equal(z.value, 0);
    var s = jsb.run('return input', '');
    assert.is_true(s.ok);
    assert.equal(s.value, '');
    var a = jsb.run('return input', []);
    assert.is_true(a.ok);
    assert.equal(a.value.@count(), 0);
  });

  test('jsbox: input is a copy', {
    var input = [a: 1];
    var r = jsb.run('input.a = 99; return input.a;', input);
    assert.is_true(r.ok);
    assert.equal(r.value, 99);
    assert.equal(input.a, 1);
  });

  test('jsbox: non-JSON results are rejected', {
    var b = jsb.run('return 1n', nil);
    assert.is_false(b.ok);
    assert.equal(b.error.kind, 'runtime');
    var c = jsb.run('var a = {}; a.self = a; return a;', nil);
    assert.is_false(c.ok);
    assert.equal(c.error.kind, 'runtime');
    var u = jsb.run('return undefined', nil);
    assert.is_false(u.ok);
    assert.equal(u.error.kind, 'runtime');
  });

  test('jsbox: Promise results are rejected', {
    var r = jsb.run('return Promise.resolve(1)', nil);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'runtime');
    assert.contains(r.error.message, 'Promise');
  });

  test('jsbox: thrown non-Error values', {
    var r = jsb.run('throw null', nil);
    assert.is_false(r.ok);
    assert.equal(r.error.kind, 'runtime');
  });

  test('jsbox: different seeds differ', {
    var a = jsb.run('return Math.random()', nil, [seed: 1]);
    var b = jsb.run('return Math.random()', nil, [seed: 2]);
    assert.is_true(a.ok);
    assert.is_true(b.ok);
    assert.is_true(a.value <> b.value);
  });

  test('jsbox: non-numeric limits use defaults', {
    var r = jsb.run('return 1', nil, [timeout: 'x', memory: 'y', output: 'z']);
    assert.is_true(r.ok);
    assert.equal(r.value, 1);
  });

  test('jsbox: opts must be a set', {
    assert.raises({ jsb.run('return 1', nil, 'x'); }, 'opts must be a set');
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
