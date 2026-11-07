# fun-jsbox

`fun-jsbox` is a one-shot JavaScript sandbox worker for Fun. Fun stays the
trusted orchestrator; machine-written JavaScript runs in a separate process and
communicates only with JSON.

This is the minimal implementation. It is small on purpose: no module loader,
no console, no file, network, or process bindings, and no host objects other
than the JSON `input` argument.

## Build

```sh
src/prj/fun/build-jsbox.sh
# -> fun/fun-jsbox
```

The script fetches QuickJS-ng v0.18.0 into `src/3rd/quickjs-ng` on demand and
verifies the tarball SHA256. To use another checkout:

```sh
QJS_SRC=/path/to/quickjs-ng src/prj/fun/build-jsbox.sh
```

`EXTRA_CFLAGS`, `OUT`, `OBJ`, and `CC` are honoured for debug or alternate
builds:

```sh
EXTRA_CFLAGS="-O1 -g -fstack-protector-all -D_FORTIFY_SOURCE=2" \
OUT=/tmp/fun-jsbox-debug OBJ=/tmp/jsbox-obj src/prj/fun/build-jsbox.sh
```

Only the QuickJS-ng core is linked (`quickjs.c`, `libregexp.c`, `libunicode.c`,
`dtoa.c`). `quickjs-libc` is deliberately not linked, so there is no `std`,
`os`, `console`, or module loader.

QuickJS-ng is MIT-licensed. After the fetch, its license text is at
`src/3rd/quickjs-ng/LICENSE`; ship it with any binary distribution.

## Use from Fun

```fun
use 'fun/lib/lib-jsbox.fun' as jsb;

var r = jsb.run(
  'var s = 0; for (var i = 0; i < input.rows.length; i++) s += input.rows[i].n; return {sum: s};',
  [rows: [[n: 1], [n: 2], [n: 3]]],
  [timeout: 200, memory: 4 * 1024 * 1024, output: 256 * 1024]
);

if r.ok then
  ?. r.value.sum;          // 6
else
  ?. r.error.kind;         // syntax / runtime / timeout / oom / ...
end if;
```

Worker resolution order:

1. `FUN_JSBOX` environment variable
2. `fun-jsbox` next to the running interpreter (`0.arg()`)
3. `fun-jsbox` on `PATH`, only when the interpreter path is unavailable

In a service, set `FUN_JSBOX` to an absolute path in a directory that
untrusted users cannot write to. The wrapper does not search `PATH` when the
interpreter path is known.

`lib-jsbox.fun` uses `process.run` and `env.fun`, so the orchestrator must be an
FFI-enabled normal build. A `-safe` build fails while loading `lib-host`
(`getapi` is denied); it is not the intended controller for this module. The JS
itself is untrusted; the Fun controller is trusted and should validate the JSON
result before using it.

## JavaScript contract

The worker builds:

```js
(function (input) {
  "use strict";
  // deterministic prelude: seeded Math.random, fixed Date.now
  // your code
})
```

Your code is a function body. It receives `input` as a JSON value and must
`return` a JSON-serializable value. There is no `require`, `process`, `std`,
`os`, `console`, or `print`.

Modern JavaScript is available because the engine is QuickJS-ng: `const`, `let`,
arrow functions, classes, template literals, BigInt, Promise, and so on. Do not
rely on timers, network, or the filesystem; those bindings do not exist.

JSON numbers are IEEE-754 doubles. `NaN` and `Infinity` are serialized as
`null` by `JSON.stringify`; return a string if the caller must distinguish
them. Fun `Int64` values above 2^53 lose precision at the JSON boundary (the
same caveat as ROADMAP D-04). Pass large identifiers, money in minor units, and
64-bit hashes as decimal strings if the exact value matters.

`input` must be acyclic JSON data. Fun's set construction and `@toJson` can
overflow the native stack on nested cyclic collections; data parsed from JSON
is safe, but programmatically built cycles are not. This is a core Fun
limitation, not a jsbox protocol issue.

## Protocol

Request (stdin, one JSON object):

```json
{
  "protocol": 1,
  "op": "eval",
  "code": "return input.a + input.b;",
  "input": {"a": 1, "b": 2},
  "limits": {
    "timeout_ms": 200,
    "memory_bytes": 4194304,
    "output_bytes": 262144
  },
  "seed": 1,
  "now_ms": 0
}
```

Response (stdout, one JSON object):

```json
{
  "protocol": 1,
  "engine": "quickjs-ng",
  "engine_version": "0.18.0",
  "ok": true,
  "value": {"sum": 3},
  "error": null,
  "usage": {
    "wall_ms": 1,
    "timeout_ms": 200,
    "memory_bytes": 4194304,
    "output_bytes": 262144
  }
}
```

Error response:

```json
{
  "protocol": 1,
  "engine": "quickjs-ng",
  "engine_version": "0.18.0",
  "ok": false,
  "value": null,
  "error": {
    "kind": "syntax",
    "name": "SyntaxError",
    "message": "variable name expected",
    "line": 1,
    "column": 5,
    "stack": "    at <jsbox>:2:5\n",
    "retryable": true
  },
  "usage": {"wall_ms": 1}
}
```

`kind` is one of `syntax`, `runtime`, `timeout`, `oom`, `output_limit`,
`input_limit`, `worker`, `protocol`, `internal`.

## Limits

| Limit | Default | Hard cap | Enforcement |
|---|---|---|---|
| code size | 4 MiB | 4 MiB | Fun wrapper |
| request size | 16 MiB | 16 MiB | worker stdin reader |
| timeout | 200 ms | 10 s | QuickJS interrupt handler + `process.run` kill |
| memory | 4 MiB | 64 MiB | `JS_SetMemoryLimit` + `RLIMIT_AS` |
| output | 256 KiB | 4 MiB | worker JSON size check |
| stack | memory/2 | 2 MiB | `JS_SetMaxStackSize` |
| processes | 0 | 0 | `RLIMIT_NPROC` |
| open files | 16 | 16 | `RLIMIT_NOFILE` |

The worker also applies `RLIMIT_CPU`, `RLIMIT_FSIZE`, and disables core dumps.
These are backstops. The parent `process.run` timeout is the hard kill for
cases the engine cannot interrupt, such as a catastrophic regexp.

## Determinism

- `Math.random` is replaced with a seeded generator.
- `Date.now` returns the request's `now_ms` (default 0).
- Each request runs in a fresh process and context.
- `new Date()` is still platform-dependent; pass time in as input if you need
  it.

## Security status

This is the MVP, not the final sandbox. Current properties:

- separate process per evaluation
- no host bindings beyond JSON `input`
- no `quickjs-libc`, so no file/network/process/module APIs
- source only; the worker never accepts bytecode
- memory, timeout, output, stack, process, and fd limits
- `RLIMIT_*` backstops

Not done yet:

- seccomp-bpf allowlist
- `unshare`/bubblewrap/nsjail network and mount isolation
- Windows Job Object limits and macOS sandbox profile
- an output cap inside `process.run` (the worker caps itself, but a compromised
  worker could still write a large stdout before exiting)
- bytecode cache (only useful for reviewed, trusted scripts; never for
  machine-written code)

For adversarial input, add the process hardening before trusting the result as
a security boundary.

## Tests

```sh
fun/test/run-jsbox-test.sh
```

This builds the worker and runs `fun/test/jsbox_test.fun`, covering the happy
path, syntax/runtime errors, timeout, OOM, output limit, determinism, absent
host APIs, Unicode, one-shot process isolation, falsy JSON results, input
copying, non-JSON results, thrown non-Error values, seeds, and invalid option
types.
