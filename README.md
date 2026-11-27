# Fun Language

**Small runtime, long reach: from glue code to machine code.**

Fun is a ~0.3 MB, zero-dependency scripting language, in production since
2010, that spans JSON/FD data, daily glue code, FFI, runtime C, JIT and raw
machine code.

**~0.3 MB** runtime · **0** external deps · **Windows 95 → LoongArch64** · **15+ years**

[Install](#quick-start) · [Tutorial](docs/tutorial.md) · [Manual](https://funlang.org/man.htm) · [Why Fun](#why-fun)

**English** (this file) · [简体中文](README.zh.md)

- Version: **9.5.7** · Website: <https://funlang.org> · License: MIT ([terms](#license)) · [Roadmap](ROADMAP.md)

```fun
use 'lib-set.fun';

var nums = [1, 2, 3, 4, 5];
var doubled = nums | map(a -> a * 2);
?. doubled.@toJson();   # [2,4,6,8,10]

class Number(me)
  this['#'] = you -> (me + you) * me * you;
end class;
var n = Number(2);
?. n .# 3;              # 30
```

**For AI agents.** A machine-facing ontology lives in [`ontology/`](ontology/README.md):
stable concept ids, runnable examples, token-budgeted cards, `llms.txt`, and an
MCP server with search, context, check and run. Design notes:
[docs/ai-ontology.md](docs/ai-ontology.md). Quick lookup: `fun explain json`.

---

## Highlights

**Paste a C prototype and call it.** On Windows, `CWin32API` parses the
declaration, builds the FFI signature, and exposes named arguments:

```fun
use 'lib-cwinapi.fun';

var msgBox = CWin32API('user32.dll',
  'int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);');
msgBox.call([lpText: 'Hello from Fun', lpCaption: 'Fun', uType: 0]);
```

**Paste a C struct and get the layout.** `CStruct` computes field offsets,
arrays and padding, and gives you a pointer-addressable buffer:

```fun
use 'lib-cstruct.fun';
var point = CStruct('struct Point { int x; int y; };', [x: 3, y: 4]);
?. point.@totalSize;    # 8
?. point.@toPtr() != 0; # true
```

**Go below the FFI when you need to.** The same script can compile C with the
bundled Tiny C Compiler, JIT it, or emit inline assembly, and native code can
call back into Fun through `@toCallback`. See
[the capability ladder](#the-capability-ladder).

**Ship one file, or lock it down.** `fun pack` embeds the app and its
libraries into one executable. `fun-safe` is a separate build with native
code, arbitrary memory access and file/compile access removed, for plugins and
untrusted scripts.

**Batteries included, not bolted on.** The same library ships an HTTP
server/client (CORS, JWT, sessions, multipart), cron, logging, runtime traces,
an ORM, YAML/XML/TOML/CSV, JSON Schema, desktop UI and a worker pool.

**Embed in three lines.** `Run(PChar('script.fun')); Run(source); Run(-1);`
turns the whole runtime into an embeddable `fun.dll`.

**Legacy Windows still counts.** Most runtimes chase the newest OS; Fun keeps
legacy systems running. The 32-bit build still runs on Windows 95 OSR2 (UI
included) and Windows NT 3.5, with FFI and machine code intact. See
[Windows 95](https://funlang.org/art/fun-on-win95.htm) and
[NT 3.5](https://funlang.org/art/fun-on-nt35.htm).

---

## Why Fun

In one sentence: **Fun is a scripting language that goes all the way from JSON to machine code.**

- One runtime spans the whole spectrum, from high-level data work (JSON/FD) down to low-level system programming (FFI, C at runtime, JIT, machine code);
- about 90 standard-library modules written in Fun itself ship together as one embeddable `fun.dll`;
- in AI-agent and domestic-IT scenarios, it is the lightweight glue connecting OSes, databases, chips, and business logic.

Fun is designed around a simple premise: **data and code should be equally first-class, and a script should be able to reach down to the machine without leaving the language.**

Most scripting languages either stay high-level (easy, but you hit a wall at the FFI) or force you to write C for performance-critical parts. Fun collapses that ladder into one runtime:

- Manipulate **JSON and FD** data with native list / set / tree collections;
- call arbitrary native code through a **compact FFI signature**;
- compile **C at runtime** with a bundled Tiny C Compiler;
- drop to **inline assembly / JIT** for the tightest loops;

all from pure script, in a single embeddable binary.

Fun is written in Pascal (Delphi / Free Pascal). The core is a small tree-walking interpreter with a dynamic value model, an object system, closures, and modules — deliberately compact so it can be embedded as `fun.dll` or run as a standalone `fun.exe`.

---

## Core features

- **Dynamic, data-centric value model** — numbers, strings, time, regex, and first-class collections: list (array), set, and tree, built on a variant-based runtime.
- **First-class functions** — anonymous functions, function references, currying, default and variadic parameters, and `->` pipelines.
- **Object system** — `class`, `this` / `base`, methods, and property get/set dispatch (methods, getters and setters are dispatched uniformly through the `.` operator).
- **Modules** — `use 'file.fun'` (optionally `as alias`) pulls in other scripts; an alias also exposes names imported by forwarding modules, and the runtime tracks module state and dependencies.
- **Regex as a value type** — bundled PCRE engine with inline regex literals (`/.../`) and match operators (`=~`, `!~`).
- **Built-in data formats** — JSON and **FD**, a JSON-compatible, Markdown-like format friendly to humans and to AI (see [below](#the-fd-data-format)).
- **Runtime C & machine code** — bundled Tiny C Compiler, JIT, and inline assembly (see [the capability ladder](#the-capability-ladder)).
- **C-level FFI** — paste a C prototype or use a compact signature string to call DLL/shared-library functions (see [FFI](#foreign-function-interface)).
- **Keyword aliasing** — a canonical English keyword set with pluggable alias packs (Chinese, French, custom) selected at runtime (see [below](#keyword-aliasing)).
- **Cross-platform** — Linux x64/arm64 (LoongArch64/riscv64 prerelease), macOS x64/arm64, and Windows x64; the 32-bit build still runs on Windows 95 OSR2 and NT 3.5 (see [legacy Win32](docs/building.md#legacy-win32)). The linux-x64 artifact is built in a glibc 2.17 container and linux-arm64 in a glibc 2.28 container, so Kylin V10 / UOS 20 and other old-glibc distributions run them out of the box.
- **Dual distribution** — command-line `fun.exe` and embeddable runtime `fun.dll` exporting a simple `Run` interface.
- **Self-hosted standard library** — about 90 public modules written in Fun itself, from JSON/YAML/XML to ORM, async, UI, and native bindings.

---

## Quick start

Download a prebuilt archive from
[GitHub Releases](https://github.com/funlang/fun/releases), or use the
one-line installer (macOS / Linux; verifies `SHA256SUMS`, installs under
`~/.fun`):

```bash
curl -fsSL https://raw.githubusercontent.com/funlang/fun/main/install.sh | sh
```

On Windows, extract the `.7z` with 7-Zip and double-click `install.cmd`.
Each archive ships `fun`, `fun-safe`, `fun-mt` where available, the standard
`lib/`, demos and the regression suite. See [docs/install.md](docs/install.md)
for archive details, installer options and runtime requirements.

Run a script:

```text
fun <file.fun>                # run a script (.fun / .foo / .fxx)
fun -v <file.fun>             # show compile & run timing
fun -log[:log.txt] -gui       # log output / run in GUI mode
fun -key:key_cn.ini           # load a keyword alias pack
```

Hello world (canonical keywords):

```fun
fun foo()
  ?. 'Hello, fun!';
end fun;

foo();

fun max(a, b)
  if a > b then
    result = a;
  else
    result = b;
  end if;
end fun;

?. max(1, 9);
?. max(9, 1);
```

Run:

```text
> fun fun/demo/fun.fun
Hello, fun!
9
9
```

---

## Documentation

Start with the [tutorial](docs/tutorial.md); use the website
[manual](https://funlang.org/man.htm) for exact language rules.

| Document | What it covers |
| -------- | -------------- |
| [Tutorial](docs/tutorial.md) | Guided path: first script, values, collections, classes, files, packages, HTTP, workers, native code. |
| [Standard library guide](docs/standard-library.md) | Module map and detailed usage for workers, logging, runtime, cron, HTTP, CLI, IO, formats and schema. |
| [Installing](docs/install.md) | Release archives, one-line installer, Windows installer, runtime requirements. |
| [Building](docs/building.md) | Native and cross builds, capability matrix, third-party dependencies, safe builds, CI. |
| [Tooling](docs/tooling.md) | `package.fun`, `fun package`, `fun run`, `fun test`, `fun pack`. |
| [Manual](https://funlang.org/man.htm) | Language reference, chapter by chapter. |

---

## A taste of Fun

Two quick, self-contained snippets that show both ends of the language (the full files live in `fun/demos/benchmarks/`).

Custom operators on classes, first-class functions, composition, and pipelines:

```fun
# a class with a custom operator
class Number(me)
  this['#'] = you -> (me + you) * me * you;
end class;
var $ = Number(2);
?. $ .# 3;            # (2 + 3) * 2 * 3 = 30

# first-class functions, composition & pipelines
var f = a -> a * 2;
var g = a -> a + 3;
?. g(f(1 + 2) + 3);   # 12
?. 1 + 2 | f + 3 | g; # 12 (same, pipelined)
```

A data pipeline that turns a query string into a map using regex and collection combinators:

```fun
use 'lib-regex.fun';
use 'lib-set.fun';
var q = 'a=1&b=2&c=';
var parseQuery = s -> (s | split(/&/) | map(sp_eq) | fromPairs);
?. parseQuery(q).@toJson(1);  # {"a":"1","b":"2","c":""}
```

See [`test-high-level-language.fun`](fun/demos/benchmarks/test-high-level-language.fun) for the complete version.

---

## Packages and testing

A project is a directory with a `package.fun` manifest:

```text
fun package init myapp          # package.fun + src/main.fun
fun package init mylib --lib    # package.fun + src/lib.fun
fun package tidy                # install pinned revisions into ~/.fun
fun run [args...]               # run the manifest bin
fun test                        # run every *_test.fun
fun pack                        # embed app + libraries into one executable
```

Tests use `test.fun` and `*_test.fun` files:

```fun
use 'test.fun';
test('adds', {
  assert.equal(add(1, 2), 3);
});
```

`fun test` runs each file in a child process and exits non-zero on failure.
See [docs/tooling.md](docs/tooling.md) for manifest fields, dependency rules,
assertions, `skip`/`todo`, and packing options.

---

## The capability ladder

What makes Fun unusual is how far a script can go without a separate toolchain:

| Layer        | Facility                          | Backing                                          |
| ------------ | --------------------------------- | ------------------------------------------------ |
| High-level   | JSON / FD data, list / set / tree | native collections and parsers                  |
| Native calls | `dll.getapi(name, 'signature')`   | FFI with a compact signature convention         |
| C at runtime | `ccompile(code, ...)`             | bundled Tiny C Compiler (`libtcc.dll`/`.so`/`.dylib`) |
| JIT          | `NewJit(...)`                     | dispatch between C (TCC) and assembly           |
| Machine code | `Assembly(code, ...).Load()`      | inline assembly, executable memory allocation   |

For example, `lib-tcc` loads `libtcc.dll` on Windows, `libtcc.so` on Linux and `libtcc.dylib` on macOS x64, and exposes `tcc_new`, `tcc_compile_string`, `tcc_get_symbol`, ... so you can compile C source from a string and call the resulting symbol immediately. `lib-asm` allocates executable memory, writes machine code, and invokes it; `lib-jit` picks the right path based on the source (`#!c` → TCC, otherwise assembly).

A single script can mix both: `NewJit` compiles C **and** inline assembly at runtime, and each can call straight back into a Fun function (`@toCallback`). See [`test-jit-cb.fun`](fun/demos/benchmarks/test-jit-cb.fun) for a complete example. The `#!C` path is portable; assembly is architecture-specific.

---

## The FD data format

FD is a data format designed to be **readable by humans and by AI**, and interoperable with JSON:

- JSON-compatible structure (nested keys, arrays);
- indentation-based, Markdown-like syntax;
- optional SSE compression;
- bidirectional conversion with JSON (`@toJson`, `getJson`).

```text
# FD format (Markdown-like: indentation + space-separated keys)
person
  name Zhang Weidong
  age 46
  skills
    - pascal
    - c
    - fun

# equivalent JSON
{"person": {"name": "Zhang Weidong", "age": 46, "skills": ["pascal", "c", "fun"]}}
```

Its defining trait is that **FD is self-describing**: the parser in `lib-fd.fun` is generated from a BNF grammar written in FD itself (`fd.bnf.fd`). The grammar file `src/parse/bnf/fun.ebnf` documents the language grammar in the same spirit.

FD value rules (shared by the interpreter, `fd.js`/`fd2.js`, and the BNF reader) are documented in the [manual](https://funlang.org/man.htm) and `lib-fd.fun`; the key points are RFC 8259 numbers, `true`/`false`/`null` only, raw strings by default, and last-wins duplicate keys.

---

## Foreign function interface

There are two entry points: paste a C prototype for readable bindings, or use
a compact signature when you want full control.

### Paste a C prototype

On Windows, `CWin32API` takes the declaration as it appears in the C header and
exposes named arguments:

```fun
use 'lib-cwinapi.fun';

var msgBox = CWin32API('user32.dll',
  'int MessageBoxA(HWND hWnd, LPCSTR lpText, LPCSTR lpCaption, UINT uType);');
msgBox.call([lpText: 'Hello from Fun', lpCaption: 'Fun', uType: 0]);
```

`CStruct` applies the same idea to data: paste a `struct` declaration and get
field offsets, padding and a layout-compatible buffer. See the
[standard library guide](docs/standard-library.md#c-declarations-and-structures)
for the supported types and limits.

### Compact signatures

For everything else, Fun exposes native functions through a compact
**signature-string** convention. Examples drawn from the standard library:

```fun
'kernel32'.getapi('VirtualAlloc', 'iiii:i');  // 4 int args -> int
'tcc'.getapi('tcc_new', 'v:i');               // void arg -> int
```

The signature encodes each argument's type, then `:`, then the return type (`i` = int, `s` = string, `v` = void, `d` = double, etc.). The same mechanism drives COM (`lib-winole`), the Windows API (`lib-winapi`), and the C runtime.

`getapi` is per-platform: `winapi.pas` on 32-bit Windows, and `lffi.pas` - backed by FPC's bundled libffi - on Linux, macOS and win64 (there it resolves against `ffi.dll`).

A bare `var x` argument for a `p` parameter is an OUT/INOUT pointer on both backends: the engine passes a pointer-width cell and copies the result back into `x`. For explicit control (or for a caller-owned buffer) pass the address yourself with `buf.toNum(-1)`.

---

## Keyword aliasing

The interpreter's canonical keywords are English (`fun`, `if`, `then`, `loop`, `class`, ...). Because keywords are resolved through an alias layer (`ParseAlias`), you can supply **pluggable alias packs** at startup:

```text
fun.exe -key:key_cn.ini   # Chinese keywords (函数=fun, 如果=if, ...)
fun.exe -key:key_fr.ini   # French keywords
```

Included packs: `key_cn.ini` (简体中文), `key_fr.ini` (français), and `key_pua.ini` (custom/private-use). The language itself is keyword-neutral — aliases are a localization/accessibility feature, not a different language.

---

## Embedding with fun.dll

`fun.dll` is the embeddable runtime for integrating Fun scripts into third-party applications:

```pascal
Run(PChar('script.fun'));  // compile the script
Run(scriptContent);        // execute it
Run(-1);                   // release
```

- **Free use (MIT)**: personal study, internal tools, and products released under an open-source license.
- **Commercial use**: embedding `fun.dll` in a closed-source commercial product (exe/dmg/apk or a SaaS backend) requires a commercial license — see [`LICENSE.dll`](LICENSE.dll).

---

## Repository layout

```text
fun/
├── src/
│   ├── core/          # Interpreter core (value model, object system, control flow, IO)
│   ├── parse/         # Lexer/parser
│   │   └── bnf/       #   Grammar: fun.ebnf, yacc.y, lex.l (generates .inc/.cod)
│   ├── lib/           # Built-in runtime library (winapi, winole, UI, host, etc.)
│   ├── regex/pcre/    # Bundled PCRE regex engine
│   ├── 3rd/           # Third-party components (KOL)
│   ├── utils/         # Utility functions
│   └── prj/fun/       # Projects & build scripts (funcmd.dpr, Delphi/FPC)
├── fun/
│   ├── lib/           # Standard library (pure Fun, ~90 public modules)
│   ├── demo/          # Language syntax demos
│   ├── demos/         # Full applications & benchmarks
│   └── key_*.ini      # Keyword alias packs (CN / FR / PUA)
├── docs/              # Tutorial, standard library, install, build and tooling guides
└── LICENSE*           # License files
```

---

## Building

Native builds:

```sh
cd src/prj/fun && ./make-linux-x86_64.sh   # Linux x86_64
cd src/prj/fun && ./make-macos.sh          # macOS (Homebrew FPC)
```

```bat
cd src\prj\fun
make-win64.bat
```

Platform capability matrix (default build plus the opt-in `fun-safe` and
`fun-mt` variants):

| Platform       | regex | FFI | runtime C (tcc) | asm | safe build | worker build |
| -------------- | ----- | --- | --------------- | --- | ---------- | ------------ |
| linux-arm64    | yes   | yes | yes             | yes | yes        | yes          |
| linux-loongarch64 | yes | yes | no             | yes | yes        | yes          |
| linux-riscv64  | yes   | yes | no              | yes | yes        | yes          |
| linux-x64      | yes   | yes | yes             | yes | yes        | yes          |
| macos-arm64    | yes   | yes | yes             | yes | yes        | yes          |
| macos-x64      | yes   | yes | yes             | yes | yes        | yes          |
| win-x64        | yes   | yes | yes             | yes | yes        | yes          |

Legacy Win32 is not an afterthought: the 32-bit build still runs on Windows 95
OSR2 (UI included) and NT 3.5. These are compatibility probes, not release
gates; see [Windows 95](https://funlang.org/art/fun-on-win95.htm) and
[NT 3.5](https://funlang.org/art/fun-on-nt35.htm).

The macOS, Linux aarch64, LoongArch64 and riscv64 rows are cross-built on Linux
x86_64 with bootstrapped FPC toolchains. Third-party sources (PCRE, TCC, zlib,
libffi) are not vendored; missing ones degrade the build instead of failing.
See [docs/building.md](docs/building.md) for cross-build commands, toolchain
requirements, dependency layout, safe builds and CI details.

---

## Standard library

The standard library in [`fun/lib`](fun/lib) is written in pure Fun: about 90
public modules (140 `.fun` files including platform variants and internal
helpers). The full module map and usage notes live in the
[standard library guide](docs/standard-library.md).

- **Data**: `lib-json`, `lib-fd`, `csv`, `toml`, `jsonschema`, `lib-yaml`, `lib-xml`, `lib-base64`, `lib-cstruct`, `lib-md5`, `lib-crypt`, `lib-hmac`, `lib-url`
- **Utility**: `uuid`, `lib-utils`, `lib-param`
- **Collections / algorithms**: `lib-set`, `lib-tree`, `lib-stack`, `lib-dyns`, `lib-math`, `lib-bnf`
- **Text**: `lib-string`, `lib-regex`, `lib-match`, `lib-unicode`
- **System / IO**: `lib-file`, `lib-os`, `lib-host`, `lib-path`, `lib-stream`, `lib-input`, `lib-zlib`, `lib-sse-compress`, `env`, `cli`, `fs`, `io`, `process`, `logging`, `runtime`, `cron`, `lib-time`, `lib-cmdline`, `lib-proc`
- **Network**: `lib-winsock`, `lib-netif`, `lib-icmp`, `lib-ajax`, `lib-jsonrpc`, `http-server`, `http-client`, `http-auth`, `http-bearer`, `http-cors`, `http-multipart`, `http-session`, `jwt`, `tls`
- **Databases**: `lib-orm`, `lib-orm-pro`, `lib-orm-gen`, `lib-orm-rpc`, `lib-orm-cte`, `lib-ado`, `lib-ado-schema`
- **Native / low-level**: `lib-winapi`, `lib-winole`, `lib-registry`, `lib-cwinapi`, `lib-cstruct`, `lib-tcc` (C compile), `lib-jit`, `lib-asm`, `lib-asm-pro`, `lib-eval`
- **UI**: `lib-ui`, `lib-ui-base`, `lib-dialog`, `lib-trayicon`
- **Concurrency / async**: `lib-async`, `lib-jsasync`, `lib-bind`, `lib-message`, `lib-worker`
- **Sandbox**: `lib-jsbox`
- **Testing**: `test` (registration and assertions for `fun test`)

A few starting points:

- **Workers** — `lib-worker` needs the opt-in `fun-mt` build. A worker owns its AST and heap; results cross as strings, and `Shared`/`Channel` copy values. See [workers](docs/standard-library.md#workers-and-the-fun-mt-build) and [`worker-model.md`](fun/lib/worker-model.md).
- **Logging** — configure once, then use named loggers (`logging.getLogger`); see [logging](docs/standard-library.md#logging).
- **Runtime diagnostics** — `runtime.source`, `runtime.stack` and `runtime.lastError` expose file, line, function and stack; see [runtime diagnostics](docs/standard-library.md#runtime-diagnostics).
- **Cron and HTTP** — `CronScheduler`, `HttpMultipartWriter`, signed cookies and JWT share the same single-threaded model; see [cron](docs/standard-library.md#cron-scheduling) and [HTTP helpers](docs/standard-library.md#http-helpers).
- **CLI, files, streams and processes** — `cli`, `fs`, `io`, `process`, TOML, CSV and JSON Schema are documented in the [guide](docs/standard-library.md).

---

## Examples

- [`fun/demo`](fun/demo) — syntax demos: functions, closures, currying, classes, objects, sets, regex, and exception handling.
- [`fun/demos`](fun/demos) — full applications and benchmarks: the `notepad--` editor, `odbc-search`, and performance/assembly/JIT benchmarks.
- [`fun/demos/package-demo`](fun/demos/package-demo) — a small package with a path dependency: `tidy`, `run` (project and flat mode), and `pack`.
- [`fun/demos/test-demo`](fun/demos/test-demo) — a lib-only package with tests, a shared helper, and a failing-assertion example.
- [`fun/demos/http-cors-demo`](fun/demos/http-cors-demo) — CORS preflight, credentials, exposed headers, and a browser page.
- [`fun/demos/http-bearer-demo`](fun/demos/http-bearer-demo) — Bearer token auth, 401 challenges, and a same-origin page.
- [`fun/demos/http-session-demo`](fun/demos/http-session-demo) — cookie session login/logout, SID rotation, and server-side state.
- [`fun/demos/fs-demo`](fun/demos/fs-demo) — nested directories, listing, walking, atomic write, and cleanup.
- [`fun/demos/cli-demo`](fun/demos/cli-demo) — commands, flags, aliases, env, hooks, help/version, and testable output.

---

## License

Fun is distributed under a **dual-license** model:

1. **Open-source (MIT)** — see [`LICENSE`](LICENSE). You are free to use, modify, and redistribute the source, provided the copyright notice is retained.
2. **Commercial license** (additional terms that apply only to these closed-source redistribution cases):
   - Substantially modifying the kernel and commercially distributing the result closed-source — see [`LICENSE.custom`](LICENSE.custom);
   - Embedding `fun.dll` in a closed-source commercial product or SaaS backend — see [`LICENSE.dll`](LICENSE.dll).

**In short**: internal use, study/research, and releasing modified versions under an open-source license (MIT/GPL etc.) are all free. A commercial license is needed only when you sell a modified kernel or `fun.dll` as a closed-source commercial product. Commercial licenses are one-time, priced per project/company — contact &lt;zwd@funlang.org&gt;.

---

© 2010-2026 Zhang Weidong &lt;zwd@funlang.org&gt;
