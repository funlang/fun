// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-jsbox: run machine-written JavaScript in a separate one-shot process.
//
//     use 'lib-jsbox.fun' as jsb;
//
//     var r = jsb.run(
//       "var s = 0; for (var i = 0; i < input.rows.length; i++) s += input.rows[i].n; return {sum: s};",
//       [rows: [[n: 1], [n: 2]]],
//       [timeout: 200, memory: 4 * 1024 * 1024, output: 256 * 1024]
//     );
//
//     if r.ok then ?. r.value; else ?. r.error.kind; end if;
//
// The worker is `fun-jsbox`, a standalone QuickJS-ng program built by
// `src/prj/fun/build-jsbox.sh`. It has no file, network, process, or module
// APIs. The JavaScript code is a pure function body: it receives `input` as a
// JSON value and must `return` a JSON-serializable value.
//
// Resolution order for the worker path:
//   1. FUN_JSBOX environment variable
//   2. fun-jsbox next to the running interpreter (0.arg())
//   3. fun-jsbox on PATH, only when 0.arg() is unavailable
//
// This module needs an FFI-enabled interpreter because process.run and
// env.fun use getapi. A -safe build fails while loading env.fun/lib-host
// (getapi is denied), so the controller must be a trusted normal build.
//
// Options (all optional):
//   timeout  milliseconds, default 200, hard cap 10000
//   memory   bytes,        default 4 MiB, hard cap 64 MiB
//   output   bytes,        default 256 KiB, hard cap 4 MiB
//   seed     uint32,       default 1 (Math.random is seeded)
//   now      milliseconds, default 0 (Date.now is fixed)
//
// Return value:
//   [ok: true,  value: <json>, error: nil, usage: [...]]
//   [ok: false, value: nil,   error: [kind, name, message, line, column,
//                                     stack, retryable], usage: [...]]
//
// Error kinds: syntax, runtime, timeout, oom, output_limit, input_limit,
// worker, protocol, internal. Syntax/runtime errors carry 1-based line and
// column numbers so a model can repair the script.

use 'process.fun';
use 'lib-path.fun';
use 'env.fun';

var _JB_TIMEOUT = 200;
var _JB_MEMORY = 4 * 1024 * 1024;
var _JB_OUTPUT = 256 * 1024;
var _JB_MAX_TIMEOUT = 10000;
var _JB_MAX_MEMORY = 64 * 1024 * 1024;
var _JB_MAX_OUTPUT = 4 * 1024 * 1024;
var _JB_MAX_CODE = 4 * 1024 * 1024;

fun _jbOpt(opts, name, def)
  result = def;
  if opts = nil then return; end if;
  try
    if opts.@has(name) then
      var v = opts[name];
      if not v.eq(nil) then result = v; end if;
    end if;
  except
    raise 'jsbox: opts must be a set';
  end try;
end fun;

fun _jbClamp(v, def, lo, hi)
  if v.eq(nil) then result = def; return; end if;
  var t = v.type();
  if not (t.eq(3) or t.eq(5)) then result = def; return; end if;
  if v < lo then result = lo; return; end if;
  if v > hi then result = hi; return; end if;
  result = v;
end fun;

fun _jbError(kind, name, message, retryable)
  result = new [
    protocol: 1,
    ok: false,
    value: nil,
    error: new [
      kind: kind,
      name: name,
      message: message,
      line: 0,
      column: 0,
      stack: '',
      retryable: retryable
    ],
    usage: new []
  ];
end fun;

fun _jbWorker()
  var p = env.get('FUN_JSBOX');
  if not p.eq(nil) and not p.eq('') then result = p; return; end if;
  var exe = 0.arg();
  if not exe.eq(nil) and not exe.eq('') then
    result = PathJoin([PathDir(exe), 'fun-jsbox']);
  else
    result = 'fun-jsbox';
  end if;
end fun;

fun _jbRunProcess(text, timeout)
  var p = _jbWorker();
  try
    result = process.run(p, [], [stdin: text, timeout: timeout]);
  except
    raise 'jsbox: cannot start ' & p & ' (' & ('' & @) & ')';
  end try;
end fun;

fun run(code, input, opts)
  if not code.type().eq(8) then
    raise 'jsbox: code must be a string';
  end if;
  if code.length() > _JB_MAX_CODE then
    result = _jbError('input_limit', 'RangeError', 'code exceeds the size limit', false);
    return;
  end if;

  var timeout = _jbClamp(_jbOpt(opts, 'timeout', _JB_TIMEOUT), _JB_TIMEOUT, 1, _JB_MAX_TIMEOUT);
  var memory = _jbClamp(_jbOpt(opts, 'memory', _JB_MEMORY), _JB_MEMORY, 256 * 1024, _JB_MAX_MEMORY);
  var output = _jbClamp(_jbOpt(opts, 'output', _JB_OUTPUT), _JB_OUTPUT, 1024, _JB_MAX_OUTPUT);
  var seed = _jbOpt(opts, 'seed', 1);
  var now = _jbOpt(opts, 'now', 0);

  var req = new [
    protocol: 1,
    op: 'eval',
    code: code,
    input: input,
    limits: new [
      timeout_ms: timeout,
      memory_bytes: memory,
      output_bytes: output
    ],
    seed: seed,
    now_ms: now
  ];

  var text = nil;
  try
    text = req.@toJson(0, json: true);
  except
    result = _jbError('protocol', 'TypeError', 'input is not JSON-serializable: ' & ('' & @), false);
    return;
  end try;

  var r = nil;
  try
    r = _jbRunProcess(text, timeout + 1000);
  except
    result = _jbError('worker', 'WorkerError', '' & @, false);
    return;
  end try;

  if r.timedOut then
    result = _jbError('timeout', 'TimeoutError', 'worker exceeded the hard timeout', true);
    return;
  end if;
  if not r.ok then
    var why = r.stderr;
    if why.eq(nil) or why.eq('') then why = 'worker exited with code ' & ('' & r.exitCode); end if;
    result = _jbError('worker', 'WorkerError', why, false);
    return;
  end if;

  var resp = nil;
  try
    resp = r.stdout.getJson(json: true);
  except
    result = _jbError('protocol', 'ProtocolError', 'invalid worker response: ' & ('' & @), false);
    return;
  end try;
  if resp.eq(nil) then
    result = _jbError('protocol', 'ProtocolError', 'worker response is not an object', false);
    return;
  end if;
  if resp.ok.eq(nil) then
    result = _jbError('protocol', 'ProtocolError', 'worker response has no ok field', false);
    return;
  end if;
  result = resp;
end fun;
