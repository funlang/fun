# Standard library guide

The standard library in [`fun/lib`](../fun/lib) is written in pure Fun: about
90 public modules. The directory has 135 `.fun` files in total, including
platform variants and internal helpers; six modules need Windows, raw sockets,
or a macOS-only backend.

This guide is the detailed companion to the summary in the README. It covers
the module map, the larger runtime libraries, and the edge cases that are easy
to get wrong. For syntax and language semantics, see the
[manual](https://funlang.org/man.htm); for a guided introduction, see the
[tutorial](tutorial.md).

## Contents

- [Module map](#module-map)
- [Workers and the `fun-mt` build](#workers-and-the-fun-mt-build)
- [Logging](#logging)
- [Runtime diagnostics](#runtime-diagnostics)
- [Cron scheduling](#cron-scheduling)
- [HTTP helpers](#http-helpers)
- [Environment variables](#environment-variables)
- [Command-line programs](#command-line-programs)
- [Filesystem](#filesystem)
- [Byte streams and process stdio](#byte-streams-and-process-stdio)
- [Pipes](#pipes)
- [Child processes](#child-processes)
- [TOML](#toml)
- [CSV](#csv)
- [JSON Schema](#json-schema)
- [C declarations and structures](#c-declarations-and-structures)
- [Platform-split convention](#platform-split-convention)

---

## Module map

- **Data**: `lib-json`, `lib-fd`, `csv`, `toml`, `jsonschema`, `lib-yaml`, `lib-xml`, `lib-base64`, `lib-cstruct`, `lib-md5`, `lib-crypt`, `lib-hmac`, `lib-url`
- **Utility**: `uuid`, `lib-utils`, `lib-param`
- **Collections / algorithms**: `lib-set`, `lib-tree`, `lib-stack`, `lib-dyns`, `lib-math`, `lib-bnf`
- **Text**: `lib-string`, `lib-regex`, `lib-match`, `lib-unicode`
- **System / IO**: `lib-file`, `lib-os`, `lib-host`, `lib-path`, `lib-stream`, `lib-input`, `lib-zlib`, `lib-sse-compress`, `env`, `cli`, `fs`, `io`, `process`, `logging`, `runtime`, `cron`, `lib-time`, `lib-cmdline`, `lib-proc`
- **Network**: `lib-winsock`, `lib-netif`, `lib-icmp`, `lib-ajax`, `lib-jsonrpc`, `http-server`, `http-client`, `http-auth`, `http-bearer`, `http-cors`, `http-multipart`, `http-session`, `jwt`
- **Databases**: `lib-orm`, `lib-orm-pro`, `lib-orm-gen`, `lib-orm-rpc`, `lib-orm-cte`, `lib-ado`, `lib-ado-schema`
- **Native / low-level**: `lib-winapi`, `lib-winole`, `lib-registry`, `lib-cwinapi`, `lib-cstruct`, `lib-tcc` (C compile), `lib-jit`, `lib-asm`, `lib-asm-pro`, `lib-eval`
- **UI**: `lib-ui`, `lib-ui-base`, `lib-dialog`, `lib-trayicon`
- **Concurrency / async**: `lib-async`, `lib-jsasync`, `lib-bind`, `lib-message`, `lib-worker`
- **Sandbox**: `lib-jsbox`
- **Testing**: `test` (registration and assertions for `fun test`)

## Workers and the `fun-mt` build

`lib-worker` needs the opt-in `funcmd-mt` build. Release archives on the five
stable platforms ship it as `fun/fun-mt`; the LoongArch64/riscv64 nightly
prerelease stages include it too. From source use
`src/prj/fun/make-linux-x86_64-mt.sh`, `FUN_THREADS=1 make-macos.sh`, or
`make-win64-mt.bat`; for the prerelease Linux targets pass
`FUN_THREADS=1 FULL=1` to their `make-linux-*.sh` script. The default `funcmd`
stays single-threaded and reports a clear error on first use.

A worker parses its own module and owns its AST and heap, so nothing Fun-visible
is shared between threads. Results are strings; `Shared` and `Channel` copy
values in and out:

```fun
use 'lib-worker.fun';
var w = WorkerFile('job.fun', 'sum', (new [1000]).@toJson(fd: true));
var total = w.join(-1);
if w.error() <> nil then raise w.error(); end if;

Shared('counter').add('done', 1);          // named, process-wide store
Channel('log').send('job finished');       // named FIFO
```

Use `onDone` + `workerTick()` for completions on the main thread. A resident
pool (`WorkerPool(file, size)`) and cooperative `cancel()` are also available.
See [`worker-model.md`](../fun/lib/worker-model.md) for the isolation model,
idioms, and limits.

## Logging

Logging is configured once and then used through named loggers:

```fun
use 'logging.fun';

logging.config([level: 'debug']);   // per-name: [levels: ['http': 'debug']]
var logger = logging.getLogger('http');
logger.info('request', [path: '/users']);
```

The default is stderr + info + text with the call-site source;
`logging.config` replaces handlers/formatters, `newLogger` creates an
independent sink, and a formatter's `sourcePath` selects short/full/base paths.

## Runtime diagnostics

Runtime errors include the failing statement and a call-site traceback. Scripts
can inspect the same information directly:

```fun
use 'runtime.fun';

var s = runtime.source();   // [file, path, line, function, className]
var st = runtime.stack();   // innermost-first frames
runtime.root('/app');       // root for the short path, default is startup cwd

try
  risky();
except
  var e = runtime.lastError(); // message, file, path, line, function, stack
end try;
```

## Cron scheduling

`cron` provides cron expressions and fixed intervals on the same blocking,
single-threaded model:

```fun
use 'cron.fun';
var s = CronScheduler([onError: (job, err) {
  logger.error('cron job failed', [job: job['id'], error: err]);
}]);
var daily = s.addJob('0 3 * * *', cleanup);          // 5-field Vixie/POSIX
var every30s = s.addJob('0-30 * * * * *', cleanup, [withSeconds: true]);
s.every('1s', refresh);
s.removeJob(daily);
s.run();                                             // or s.tick() in a loop
```

- One scheduler per daemon; ids start at 1 and are never reused. `addJob`
  accepts ranges, lists, steps and `@hourly`/`@daily`; Quartz/AWS extensions
  (`?`, `L`, `W`, `#`, year) are rejected.
- `run()` sleeps until the nearest job (capped at 1 s) and fires a missed
  occurrence once. Due times use local wall time; intervals use a monotonic
  clock. There is no timezone/DST control yet.
- For an `HttpServer` or another poll loop, drive one pass with `tick()` and
  `nextWaitMs(maxMs)` instead of `run()`. Callbacks run synchronously, so a
  slow handler delays the loop; `tick()` is rejected while `run()` is active.
- `jobs()` items carry a `stats` sub-map: `lastRunAt`, `lastSuccessAt`,
  `errors` and `lastErrorMessage`. `lastRunAt` updates when a callback starts;
  success clears `lastErrorMessage` and updates `lastSuccessAt`, while `errors`
  stays cumulative. Statistics update even without `onError`, and `onError`
  sees the updated snapshot.
- Callback errors are not actively reported without `onError`, but the failure
  statistics remain visible in `jobs()`.

## HTTP helpers

Uploaded forms are available directly; `HttpMultipartWriter` builds the same
bodies for client uploads:

```fun
var m = req.multipart();
var name = m.fields['name'][0];
var file = m.files['avatar'][0];
```

Cookies can be signed, and `jwt` signs/verifies tokens with the same helpers:

```fun
res.signedCookie('uid', 'u1', secret, [path: '/', httpOnly: true]);
var r = req.signedCookie('uid', secret);

use 'jwt.fun';
var token = jwt.sign([sub: 'u1', exp: jwt.now() + 3600], secret);
var v = jwt.verify(token, secret, [issuer: 'app']);
```

## Environment variables

Environment variables need no platform-specific FFI:

```fun
use 'env.fun';
var home = env.get('HOME');
var port = env.get('PORT', '8080');
```

## Command-line programs

`cli` is a small command framework. A root command owns global flags and
subcommands, and every subcommand is the same `cli.command` object. Help,
version, aliases, env fallback, required flags, hooks and exit codes are built
in.

```fun
use 'cli.fun';

fun hello(ctx)
  var times = ctx.int('times');
  for i = 1 to times do
    ?. 'hello ' & ctx.string('name');
  end do;
end fun;

fun serve(ctx)
  ?. 'serving on port ' & ctx.int('port');
end fun;

var root = cli.command('demo', [
  usage: 'demo command-line tool',
  version: '1.0.0'
]);
root.flag(cli.string('name', [aliases: ['n'], value: 'world', usage: 'who to greet']));
root.flag(cli.int('times', [aliases: ['t'], value: 1, usage: 'repeat count']));
root.action(hello);
root.command(cli.command('serve', [
  usage: 'start the server',
  flags: [cli.int('port', [aliases: ['p'], value: 8080, usage: 'listen port'])],
  action: serve
]));

var code = root.run();          // nil: process arguments
if code <> 0 then cli.quit(code); end if;
```

```text
$ demo --name bob -t 2
hello bob
hello bob
$ demo serve -p 9000
serving on port 9000
$ demo --help
$ demo --version
```

`cli.command(name, opts)` accepts `usage` (a one-line summary in the parent's
command list, also shown in its own help when `description` is empty),
`usageText` (replace the generated usage line), `argsUsage`, `version`,
`description`, `aliases`, `flags`, `commands`, `action`, `before`, `after`,
`hidden`, `out`, `err` and `input`.

Flags come from `cli.string`, `cli.bool`, `cli.int`, `cli.float` and
`cli.strings`; options are `aliases`, `value` (default), `usage`, `env`
(a name or list of names), `required`, `hidden` and `placeholder`. `strings`
may be repeated. Its default list is used only when the flag is absent; the
first explicit value replaces the default. Help shows default values and env
names. A `required` flag must appear on the command line or come from env; a
default does not satisfy it, while an empty `--flag=` still counts as supplied
(validate non-empty values in the action). Flag and command names are
case-sensitive, so `-V` and `-v` are different flags. Hidden flags and commands
still parse but are omitted from help. Duplicate flag/command names and
aliases raise at construction.

Short and long forms may be mixed: `--name=value`, `--name value`, `-n value`,
`-n=value`, combined bools such as `-ab` when both are bool flags, and `--` to
stop option parsing. Boolean values accept `true/false`, `1/0`, `yes/no` and
`on/off`; bool flags do not consume the next token, so use `--flag=false`.
Integers are decimal; floats accept decimals and exponents. A non-bool option
takes the next token as its value; when that value starts with
`-`, use the attached form `--name=-x`/`-n=-x` (negative int/float values such
as `--times -1` are still accepted). Global flags belong before the subcommand;
tokens after it are parsed by the subcommand. When a command has subcommands,
its first positional token is treated as a command name, so use `--` before
positional arguments of the root action.

The action receives a context: `ctx.string/bool/int/float/strings(name)`,
`ctx.has(name)` (true only when set on the command line or by env),
`ctx.args()`, `ctx.arg(n)`, `ctx.narg()`, `ctx.command()`, and the configured
streams `ctx.out()`, `ctx.err()` and `ctx.stdin()`. Typed accessors validate the
declared flag: unknown names or a wrong type raise instead of silently returning
a zero value.
Parent flags inherited by a child stay accessible. Use canonical flag names,
not aliases, with these accessors. Env values are converted by flag type;
`strings` values are split on commas. The first present name from `env` wins.

Help and version are automatic: `--help`/`-h`, `help [command...]`, and, on a
command with `version` set, `-v`/`--version`. The `help` command exists at the
root and on commands with subcommands; a leaf command can still use `help` as a
positional value. `help`/`h` are reserved flag names, and `version`/`v` are
reserved on a command that has a version; registration raises if a flag tries
to use them. Subcommand help lists its own options; global options are listed by
the parent/root help.

Hooks run without process-level setup: `before(ctx)` may return nil/true/0 to
continue, false to stop with code 1, or a nonzero integer to stop with that
code. A parent `before` runs before the child action, and a parent `after` runs
after the child action, including when the action raises. Help, version and
parse errors do not run parent hooks. `after(ctx)` runs after its action returns
or raises, once `before` has succeeded; its return value is ignored.

`run(args)` never exits the process; it returns an exit code. Pass a list for
exact control, or call `run()` to read process arguments (a leading
`.fun`/`.foo`/`.fxx` script path is dropped; an empty process argument ends the
scan). Use `cli.quit(code)` after the command has finished when the process
should exit. Mixing `?.` with redirected `out`/`err` can reorder output: `?.`
always writes to the process console, while `ctx.out()`/`ctx.err()` use the
selected writers.

Exit codes: parse errors, unknown flags/commands, bad values and missing
required flags return 2; a false hook or an exception returns 1; an integer
returned by an action becomes the exit code. Actions must return nil, a boolean
or an integer; other return types raise and return 1. `before` accepts nil, a
boolean or an integer.

Help goes to stdout and errors go to stderr by default. The default console
writer uses the process handles directly; pass `out`/`err` for captured,
redirected or non-ASCII output. Any object with `write(s)` works; actions reach
them through `ctx.out()` and `ctx.err()`, and a child's own writers override the
root's. Writers are not closed or flushed by the framework.

The optional `input` is any object with `read(n)`, using the same reader contract
as `io.fun`. It defaults lazily to `io.stdin()`, so a command that reads
`ctx.stdin()` accepts piped input without extra setup. A child's own `input`
overrides the root's; otherwise it inherits. When a child inherits, a parent hook
and the child action share the same input stream, so a hook that reads consumes
input before the action. The framework never reads, buffers or closes the
reader, and help/version do not consume it. Tests use `io.buffer` for both
output and input:

```fun
use 'io.fun';
var out = io.buffer();
var app = cli.command('demo', [out: out, err: out]);
app.flag(cli.string('name', [value: 'world']));
app.flag(cli.int('times', [value: 1]));
app.action(hello);

?. app.run(['--help']) = 0;
?. out.text().subpos('usage: demo') >= 0;
```

Input works the same way:

```fun
var source = io.buffer('hello');
var copied = io.buffer();
fun copy(ctx)
  ctx.out().write(io.readAll(ctx.stdin()));
end fun;
var cat = cli.command('cat', [input: source, out: copied]);
cat.action(copy);
?. cat.run([]) = 0;
?. copied.text() = 'hello';
```

## Filesystem

Filesystem helpers cover directories, walking and temporary entries:

```fun
use 'fs.fun';
fs.mkdirAll('build/out');
fs.walk('src', (p, isDir) { ... });
fs.atomicWrite('build/out/config.json', data);
```

`walk` and `removeAll` do not follow symbolic links (`removeAll` deletes the
link itself, including broken links); `exists/isDir/isFile` follow them.
Whole-file create/read/append stays on the built-ins — `save(data)`,
`save(data, append: true)` and `load()`.

For segmented or binary I/O, `fs.open` returns a byte-oriented file handle:

```fun
var f = fs.open('data.bin', 'r+');
f.seek(16, 0);
var head = f.read(4);
f.write(bytes);
f.close();
```

Modes are `r`, `w`, `a`, `r+`, `w+`, `a+` (an optional `b` is accepted);
mode defaults to `r`, and `a`/`a+` append writes. Methods are `read(n)`,
`write(data)`, `seek(offset, whence)`, `tell()`, `eof()`, `flush()` and
`close()`; `whence` defaults to 0 (start) and may be 1 (current) or 2 (end).
`read` returns a byte string
(characters 0..255) and `write` writes each character's low byte. Open/I/O
failures raise; `read` at EOF returns `''`. Call `close()` explicitly.
Read/write switching follows C stdio: `seek` before writing after reading;
`seek` or `flush` before reading after writing. Offsets are 64-bit on 64-bit
hosts; large literals need arithmetic construction (e.g. `0xFFFFFFFF + 1`).
On Windows `fs.open` requires a 64-bit build; 64-bit narrow-character builds
use the active ANSI code page for paths.

## Byte streams and process stdio

Generic stream helpers accept any reader/writer, do not close the handle, and
treat `''` as EOF:

```fun
use 'io.fun';
var b = io.buffer('hello');
var text = io.readAll(b);        // small data only
var out = io.buffer();
var f = fs.open('copy.bin', 'r');
var n = io.copy(out, f);         // 8192-char chunks
f.close();
io.writeString(out, 'done');
```

`io.buffer` is the in-memory reader/writer (`read/write/text/length/reset`);
`io.readAll` is a convenience for small data, while `io.copy` streams. Pass
`io.buffer` where a format or helper expects a stream; `fs.open` handles work
directly. Format readers/writers never close or flush the underlying IO.

`io.scanner` walks any reader token by token, by default one line at a time
(`\n` or `\r\n`; the final line may omit the newline). `scan()` returns false
at EOF or on error; `text()` is the current token and `err()` reports
`token too long` or a reader error. `maxToken` defaults to 64 KB, and
`delimiter` replaces the newline:

```fun
use 'io.fun';
var sc = io.scanner(io.stdin());
while sc.scan() do ?. sc.text(); end do;
if sc.err() <> nil then raise sc.err(); end if;
```

Use `io.scanner(r, [delimiter: ','])` for a custom separator; the scanner never
closes the reader and may read ahead, so do not mix it with direct `read()`.

Process stdio uses the same contract:

```fun
use 'io.fun';
var input = io.stdin();
var output = io.stdout();
var errors = io.stderr();

var chunk = input.read(4096);     // may be short; '' means EOF
output.write('received ' & chunk.length() & 10.toChar());
errors.write('warning' & 10.toChar());
```

`io.stdin` is a Reader and `io.stdout`/`io.stderr` are Writers. They do not
close, flush or translate line endings, and they do not create pipes; `io.pipe`
creates pipes separately, and CLI stdin remains a later layer. Process stdio
treats strings as byte strings: on UTF-16 Windows builds each character is
written as one byte, so
ASCII and binary data round-trip unchanged; non-ASCII text must be encoded by
the caller first. Windows console code pages and UTF-16 are not translated.
Process stdio uses `getapi`, so an FFI-enabled build is required: `io.buffer`
still works in safe or FFI-less builds, but reading or writing process stdio
raises an error there. A closed pipe can terminate the process through SIGPIPE
on Unix, as usual. Do not mix `io.stdin()` with the built-in `line`/`char`/`all`
input helpers on the same stdin, and do not mix `io.stdout()` with `?.` when
output order matters: they use independent buffering/FFI paths.

## Pipes

Process pipes use the same reader/writer contract:

```fun
use 'io.fun';
var p = io.pipe();
p.writer.write('hello');
p.writer.close();                  // reader sees EOF after buffered data
var text = io.readAll(p.reader);   // 'hello'
p.close();
```

`io.pipe()` creates a blocking OS pipe; `p.reader` and `p.writer` are Reader and
Writer plus an explicit `close()`, and `p.close()` closes both ends. Closing the
writer lets the reader drain buffered data and then return `''`; closing the
reader makes later reads raise; a later write may terminate the process with
SIGPIPE on Unix (not a catchable error).
`p.close()` closes both ends and discards unread data.
Pipes own their handles and must be closed explicitly; `io.readAll`/`io.copy`
never close them. Pipe buffers are finite: writing more than the OS buffer
before reading deadlocks a single-threaded script. v1 is for small payloads
only; there is no supported thread/process hand-off yet, and larger transfers
need a future streaming/process-handoff layer. Reads (including `readAll` and `copy`)
block while the pipe is empty and the writer is open; there is no timeout or
cancel. Close the writer to make an empty read finish with EOF. The pair is not
thread-safe: do not read, write or close it concurrently. `io.pipe` needs an
FFI-enabled build and uses the same byte rules as process stdio.

## Child processes

Run a child process with `process.run`:

```fun
use 'process.fun';

var r = process.run('git', ['status', '--short'], [timeout: 5000]);
if r.ok then
  ?. r.stdout;
else
  ?. r.stderr;
  ?. r.exitCode;
end if;
```

`process.run(name[, args[, opts]])` executes the command directly, without a
shell. Trailing arguments are optional; pass `nil` or an empty list for no
arguments. Options are `stdin` (a string; default `''`), `cwd` (empty
inherits the current directory), and `timeout` in milliseconds (`nil`/`0`
means no timeout), and `output` in bytes (`nil`/`0` means unlimited).
The returned object has `ok`, `exitCode`, `signal`, `timedOut`, `outputExceeded`,
`stdout`, and `stderr`. A non-zero exit is a normal result; a command that
cannot start raises.
On Unix a signal exit reports a negative `exitCode` (for example `-15`) and the
signal number; Windows reports the process exit code and `signal` is `nil`.
stdout and stderr are captured separately as raw bytes; input/output are not
encoded or line-ending translated.

The call blocks until the child exits or the timeout expires. On timeout the
direct child is terminated and waited for, and the result has `timedOut = true`
and `ok = false`. The implementation uses a single-threaded stdio pump, so
stdout and stderr cannot deadlock each other; it does not create language
threads, does not kill the whole process tree, and does not provide streaming
or interactive stdio yet. When `output` is set, stdout and
stderr share one byte budget; exceeding it terminates the direct child and
sets `outputExceeded = true` and `ok = false`. Use `sh -c` / `cmd /c` explicitly
when shell syntax is required. `process.run` needs an FFI-enabled build. On Windows
v1 stdin is backed by a temporary file (Unix uses a pipe), and the ANSI
`CreateProcessA` path does not reliably handle non-ASCII command lines or paths;
the 32-bit Unicode/Delphi path remains manual. If a descendant keeps
stdout/stderr open after the direct child exits, v1 may stop reading after a
short grace period, so late descendant output can be lost.

## TOML

TOML documents use the same reader/writer contract:

```fun
use 'toml.fun';
var f = fs.open('config.toml', 'r');
var doc = toml.reader(f).read();   // nil after the first read
f.close();

var out = io.buffer();
toml.writer(out).write(doc);
```

Tables are sets, arrays are lists, and values keep TOML scalars. Date/time,
`inf` and `nan` values are `TomlLiteral` objects (`.kind` / `.text`) so the
writer can reproduce their TOML syntax. The reader returns one document and
then `nil`; the writer writes one document. Neither closes the handle.

## CSV

CSV files stream row by row. The reader and writer wrap a file handle and do
not close it:

```fun
use 'csv.fun';
var f = fs.open('users.csv', 'r');
var r = csv.reader(f);
var row = r.read();          // nil at EOF
while row <> nil do
  ...
  row = r.read();
end do;
f.close();

var g = fs.open('out.csv', 'w');
var w = csv.writer(g);
w.write(['name', 'age']);
g.close();
```

Fields are strings and columns are strict. A blank line is a one-empty-field
record by default, so it fails the column check in a multi-column file; pass
`[skipEmptyLines: true]` to ignore completely empty lines. The writer quotes
fields when needed and uses `\n`; pass `[crlf: true]` for CRLF. The reader
accepts any object with `read(n)`, the writer any object with `write(s)`.

## JSON Schema

Data can be validated against a JSON Schema. Schemas are written in FD by
default, and JSON text or an already parsed value works too:

```fun
use 'jsonschema.fun';

var schema = 'user.schema.fd'.load();
var r = JsonSchema.check(data, schema);
if not r.ok then
  ?. r.first.path & ': ' & r.first.message;
end if;
```

Errors carry a JSON Pointer path (`/user/name`, `/tags/0`). Text input can be
parsed first with `JsonSchema.checkJson(text, schema)` or
`JsonSchema.checkFd(text, schema)`; `validJson` / `validFd` are the boolean
shortcuts, and a parse failure is reported as a normal result with keyword
`parse`.

The v0.x subset covers `type` (including lists), `properties` / `required` /
`additionalProperties`, `items` (single schema or tuple) / `additionalItems` /
`minItems` / `maxItems` / `uniqueItems`, numeric bounds, `minLength` /
`maxLength` (counted in Unicode code points), `pattern` /
`patternProperties` / `propertyNames`, `enum`, `const`, `allOf` / `anyOf` /
`oneOf` / `not`, same-document `$ref` with `$defs` / `definitions`, and
`format` for `email`, `date`, `time`, `date-time`, `uri`, `uri-reference`,
`uuid`, `ipv4`, `hostname` and `regex`. External `$ref`, `dependencies`,
`if` / `then` / `else` and `contains` are not supported yet.

## C declarations and structures

`lib-cwinapi` and `lib-cstruct` turn C declarations into Fun objects.

`CWin32API(dll, prototype, defaults)` parses a function prototype and exposes
named arguments:

```fun
use 'lib-cwinapi.fun';

var msgBox = CWin32API('user32.dll',
  'int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);');
msgBox.args.lpText = 'Hello';
msgBox.call([lpCaption: 'Fun', uType: 0]);
```

`CStruct(decl, init)` parses a `struct Name { ... }` declaration, computes
field offsets and padding, and returns a layout-compatible buffer:

```fun
use 'lib-cstruct.fun';

var point = CStruct('struct Point { int x; int y; };', [x: 3, y: 4]);
?. point.@totalSize;    // 8
?. point.@toPtr() != 0; // true
```

Supported fields include integer and char types, arrays, string pointers and
fixed strings, struct pointers, and callback fields. The parser is deliberately
small: it handles direct `struct Name { ... }` declarations, not the C
preprocessor or multi-file headers. Pointer-sized fields follow the 32-bit
Win32 layout used by `lib-cwinapi`; for pointer-heavy 64-bit APIs prefer an
explicit `getapi` signature with `p`.

## Platform-split convention

> The Windows implementation keeps the plain module name, and the Unix backend
> is `<name>-unx.fun` (Linux + macOS); the older `<name>-lnx.fun` name is kept
> as a thin wrapper on top of it. Logic shared by both lives in
> `<name>-base.fun` (not counted above). Backends that only work on Linux
> (e.g. `lib-proc`, which reads `/proc`) stay `<name>-lnx`.
> E.g. `lib-os` / `lib-os-unx` (+ `lib-os-lnx`), and `lib-unicode-base` +
> `lib-unicode` / `lib-unicode-unx`. A neutral name works as well: `use` probes
> the platform variants (macOS `-darwin`→`-unx`, Linux `-lnx`→`-unx`) and picks
> one when it exists.
