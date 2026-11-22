# A task-oriented tutorial

This tutorial is the guided path: it walks from a first script to files,
packages, HTTP, workers and native code. It complements, rather than replaces,
the two reference documents:

- [`man.htm`](https://funlang.org/man.htm) / [`man-cn.htm`](https://funlang.org/man-cn.htm) — the language manual, chapter by chapter (syntax, types, classes, regex, standard libraries).
- [`docs/standard-library.md`](standard-library.md) — the module map with usage notes for the larger libraries.
- [`README.md`](../README.md) — the project overview, platform matrix and install notes.

Every chapter ends with a "go deeper" pointer so you can jump into the manual
when you need exact rules.

---

## 1. Run a script

Install a release (see the README) or use a source build, then:

```text
fun hello.fun
```

`hello.fun`:

```fun
?. 'Hello, Fun!';
```

`?.` prints a value and a newline. A script is read top to bottom; statements
end with `;`, and `#` starts a comment. Save the file with `.fun`, `.foo` or
`.fxx`; all three are recognized.

Run a script with timing, or with a keyword pack:

```text
fun -v hello.fun
fun -key:key_cn.ini hello.fun
```

## 2. Functions, values and results

Functions use `fun ... end fun;`. The last expression assigned to `result` is
the return value; `return` exits immediately.

```fun
fun max(a, b)
  if a > b then
    result = a;
  else
    result = b;
  end if;
end fun;

?. max(1, 9);
```

Types are dynamic: numbers, strings, lists, sets, functions and objects can all
live in the same variable. Missing arguments are `nil`, and call sites may use
named arguments:

```fun
fun greet(name, punct)
  if punct = nil then punct = '!'; end if;
  result = 'Hello, ' & name & punct;
end fun;

?. greet('Fun');
?. greet(punct: '?', name: 'world');
```

Go deeper: manual chapter 2 (variables) and chapter 3 (functions).

## 3. Control flow and errors

`if`/`else`, `case`, `for`, `while`, `loop` and `try` keep the Ada-like shape:

```fun
for i = 1 to 3 do
  ?. i;
end do;

try
  raise 'boom';
except
  ?. 'caught';
end try;
```

Use `try`/`except` for recoverable failures. `raise` accepts a string or an
object; `runtime.lastError()` (see the standard-library guide) exposes the
message, file, line and stack after a failure.

Go deeper: manual chapter 1 (control flow).

## 4. Collections, JSON and FD

Lists and sets are native. JSON is the interchange format; FD is Fun's
indentation-friendly data notation.

```fun
use 'lib-set.fun';

var nums = [1, 2, 3, 4, 5];
var doubled = nums | map(a -> a * 2);
?. doubled.@toJson();          # [2,4,6,8,10]

var total = 0;
for i = 0 to nums.@count() - 1 do
  total = total + nums[i];
end do;
?. total;                      # 15

var user = [name: 'Ada', tags: ['math', 'code']];
?. user.@toJson();
```

`@toJson()` emits JSON; `@toJson(fd: true)` emits FD. Parse with
`text.getJson()` / `text.getJson(fd: true)` (or the helpers in `lib-json` /
`lib-fd`).
`user['tags'][0]` and `user.name` both work; use `@has(key)` when a value may
legitimately be `nil`.

Go deeper: manual chapter 6 (sets) and the FD section in the README.

## 5. Closures, pipes and higher-order code

Functions are values. `|` pipes a value through a function, which makes data
pipelines read left to right:

```fun
var f = a -> a * 2;
var g = a -> a + 3;
?. g(f(1 + 2) + 3);            # 12
?. 1 + 2 | f + 3 | g;          # 12
```

`map`, `filter`, `find`, `compose` and friends live in `lib-set.fun`. A closure
captures the surrounding scope:

```fun
fun counter()
  var i = 0;
  return fun(){
    i += 1;
    result = i;
  };
end fun;

var c = counter();
?. c();
?. c();
```

Go deeper: manual chapter 5 (functional programming).

## 6. Classes

`class` defines a type; the body runs as the constructor. Methods are `fun`
declarations inside the class.

```fun
class Person(name)
  var name = name;

  fun hello()
    result = 'I am ' & name;
  end fun;
end class;

var p = Person('Ada');
?. p.hello();
```

Inheritance, `this`/`base` and operator overloading are covered in manual
chapter 4. Custom operators are just fields, for example
`this['#'] = you -> ...`.

## 7. Files, streams and processes

Whole-file helpers are built in:

```fun
save('out.txt', 'hello');
var text = 'out.txt'.load();
```

For directories, walking and atomic writes use `fs.fun`; for byte-oriented
I/O use `fs.open` and the `io.fun` reader/writer contracts:

```fun
use 'fs.fun';
use 'io.fun';

fs.mkdirAll('build/out');
fs.atomicWrite('build/out/config.json', data);

var f = fs.open('data.bin', 'r');
var head = f.read(16);
f.close();

var out = io.buffer();
io.writeString(out, 'done');
```

`process.run('git', ['status', '--short'], [timeout: 5000])` runs a child
without a shell and returns `ok`, `exitCode`, `stdout` and `stderr`. Pipes and
process stdio follow the same Reader/Writer contract; see the standard-library
guide for the blocking and byte-level rules.

Go deeper: manual chapter 8 (libraries) and [`docs/standard-library.md`](standard-library.md).

## 8. Modules, packages and tests

`use 'name.fun'` imports a module. A project adds a `package.fun` manifest:

```text
fun package init myapp          # package.fun + src/main.fun
fun package init mylib --lib    # package.fun + src/lib.fun
```

Declare dependencies, then install the pinned revisions into the shared cache:

```text
fun package add hello github.com/acme/hello --version v1.0.0
fun package tidy
fun run
```

`fun pack` embeds the app and its libraries into one executable. Tests are
`*_test.fun` files using `test.fun`:

```fun
use 'test.fun';
use '../src/lib.fun';

test('adds', {
  assert.equal(add(1, 2), 3);
});
```

```text
fun test
```

Go deeper: [`docs/tooling.md`](tooling.md).

## 9. A small HTTP JSON service

`HttpServer` is a blocking, single-threaded server; handlers receive a request
and a response object.

```fun
use 'http-server.fun';

fun hello(req, res)
  res.json([ok: true, path: req.path]);
end fun;

fun echo(req, res)
  res.json([got: req.json()]);
end fun;

var s = HttpServer(8080);
s.get('/api/hello', hello);
s.post('/api/echo', echo);
s.run();
```

Run it, then `curl http://127.0.0.1:8080/api/hello`. Add middleware with
`s.Use(...)`; the shipped demos cover CORS, bearer auth, sessions and
multipart uploads. For scheduled work in the same loop, drive `cron.tick()`
from the server loop instead of calling `run()`.

Go deeper: [`fun/demos`](../fun/demos) and the HTTP/cron sections in
[`docs/standard-library.md`](standard-library.md).

## 10. Workers, cron and background work

`cron` schedules callbacks on the current thread. Worker isolation is opt-in:
use the `fun-mt` binary (the default `fun` reports a clear error).

```fun
use 'lib-worker.fun';

var w = WorkerFile('job.fun', 'sum', '[1,2,3]');
var total = w.join(-1);
if w.error() <> nil then raise w.error(); end if;
?. total;
```

A worker parses its own module and owns its AST and heap, so no Fun object is
shared. Results cross as strings; `Shared` and `Channel` copy values. For many
tasks use `WorkerPool(file, size)` with `poolMap` / `poolRun`; `cancel()` is
cooperative.

Go deeper: [`fun/lib/worker-model.md`](../fun/lib/worker-model.md).

## 11. Native capabilities, from FFI to machine code

Fun is not limited to its own runtime. The capability ladder is:

| Layer | Facility |
| ----- | -------- |
| FFI | `dll.getapi(name, 'signature')` |
| C at runtime | `ccompile(...)` through the bundled TCC |
| JIT | `NewJit(...)` picks C or assembly |
| Machine code | `Assembly(...).Load()` |

These are powerful and host-specific. Start with `lib-tcc` or `lib-jit` after
reading their module headers, and keep native calls out of untrusted scripts:
the separate `fun-safe` build removes this entire layer.

Go deeper: manual appendix and [`docs/building.md`](building.md) (capability
matrix and safe builds).

## 12. Where to go next

- Exact syntax and semantics: [manual](https://funlang.org/man.htm) / [中文手册](https://funlang.org/man-cn.htm).
- Module-by-module API notes: [`docs/standard-library.md`](standard-library.md).
- Build, cross-build and CI: [`docs/building.md`](building.md).
- Packages, tests and `fun pack`: [`docs/tooling.md`](tooling.md).
- Run real programs: [`fun/demo`](../fun/demo) (syntax) and
  [`fun/demos`](../fun/demos) (applications, HTTP demos, benchmarks).
