# Fun Language

> A lightweight, embeddable, **data-centric scripting language** whose reach extends from JSON/FD data all the way down to runtime-compiled C and raw machine code.

**English** (this file) · [简体中文](README.zh.md)

- Version: **9.0**
- Website: <https://funlang.org>
- Author: Zhang Weidong &lt;zwd@funlang.org>
- License: MIT, plus commercial terms (see [License](#license))

> **Version 9.0**: this is not a toy or a prototype — a mature language refined and production-validated for over 15 years (2010–present), with a lineage that reaches back through Nuva (2006) and TemplateScript (2005).

---

## Table of contents

- [Why Fun](#why-fun)
- [Core features](#core-features)
- [Quick start](#quick-start)
- [A taste of Fun](#a-taste-of-fun)
- [The capability ladder](#the-capability-ladder)
- [The FD data format](#the-fd-data-format)
- [Foreign function interface](#foreign-function-interface)
- [Keyword aliasing](#keyword-aliasing)
- [Embedding with fun.dll](#embedding-with-fundll)
- [Repository layout](#repository-layout)
- [Building](#building)
- [Standard library](#standard-library)
- [Examples](#examples)
- [License](#license)

---

## Why Fun

In one sentence: **Fun is a scripting language that goes all the way from JSON to machine code.**

- One runtime spans the whole spectrum, from high-level data work (JSON/FD) down to low-level system programming (FFI, C at runtime, JIT, machine code);
- 59 standard-library modules written in Fun itself ship together as one embeddable `fun.dll`;
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
- **Modules** — `use 'file.fun'` (optionally `as alias`) pulls in other scripts; the runtime tracks module state and dependencies.
- **Regex as a value type** — bundled PCRE engine with inline regex literals (`/.../`) and match operators (`=~`, `!~`).
- **Built-in data formats** — JSON and **FD**, a JSON-compatible, Markdown-like format friendly to humans and to AI (see [below](#the-fd-data-format)).
- **Runtime C & machine code** — bundled Tiny C Compiler, JIT, and inline assembly (see [the capability ladder](#the-capability-ladder)).
- **Compact FFI** — call DLL/shared-library functions with a terse signature string (see [FFI](#foreign-function-interface)).
- **Keyword aliasing** — a canonical English keyword set with pluggable alias packs (Chinese, French, custom) selected at runtime (see [below](#keyword-aliasing)).
- **Cross-platform** — Windows (32/64-bit), Linux, ARM, and Windows CE.
- **Dual distribution** — command-line `fun.exe` and embeddable runtime `fun.dll` exporting a simple `Run` interface.
- **Self-hosted standard library** — 59 modules written in Fun itself, from JSON/YAML/XML to ORM, async, UI, and native bindings.

---

## Quick start

Run a script:

```text
fun.exe <file.fun>            # run a script (.fun / .foo / .fxx)
fun.exe -v <file.fun>         # show compile & run timing
fun.exe -log[:log.txt] -gui   # log output / run in GUI mode
fun.exe -key:key_cn.ini       # load a keyword alias pack
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
> fun.exe fun/demo/fun.fun
Hello, fun!
9
9
```

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

## The capability ladder

What makes Fun unusual is how far a script can go without a separate toolchain:

| Layer        | Facility                          | Backing                                          |
| ------------ | --------------------------------- | ------------------------------------------------ |
| High-level   | JSON / FD data, list / set / tree | native collections and parsers                  |
| Native calls | `dll.getapi(name, 'signature')`   | FFI with a compact signature convention         |
| C at runtime | `ccompile(code, ...)`             | bundled Tiny C Compiler (`libtcc.dll`/`.so`)    |
| JIT          | `NewJit(...)`                     | dispatch between C (TCC) and assembly           |
| Machine code | `Assembly(code, ...).Load()`      | inline assembly, executable memory allocation   |

For example, `lib-tcc` loads `libtcc.dll` on Windows (and `libtcc.so` on Linux) and exposes `tcc_new`, `tcc_compile_string`, `tcc_get_symbol`, ... so you can compile C source from a string and call the resulting symbol immediately. `lib-asm` allocates executable memory, writes machine code, and invokes it; `lib-jit` picks the right path based on the source (`#!c` → TCC, otherwise assembly).

A single script can mix both: `NewJit` compiles C **and** inline assembly at runtime, and each can call straight back into a Fun function (`@toCallback`). The snippet below sums `1..n` — once via assembly, once via compiled C — and hands the result to a Fun callback both times (full version: [`test-jit-cb.fun`](fun/demos/benchmarks/test-jit-cb.fun)):

```fun
use 'lib-jit.fun';
fun cb(a, b)          # a Fun callback called from JIT'd code
  result = a * 2^32 + b;
end fun;

# assembly path
var asm = `#!asm i:i
    mov ecx, dword ptr [esp+04]
    @sum1ton
    push eax
    push edx
    mov  eax, <test>
    call eax
`;
var jit = NewJit(asm, names: [test: cb.@toCallback(nil, 'ii:i', true)]);
?. jit.Run(100000);

# C path (compiled at runtime with bundled TCC)
var c = `#!C ii:i
  int sum(int n, int (*test)(int, int)) {
    long long s = 0;
    for (int i = 1; i <= n; i++) s += i;
    test((int)(s >> 32), (int)(s & 0xFFFFFFFF));
    return 1;
  }
`;
jit = NewJit(c);
?. jit.call(100000, cb.@toCallback(nil, 'ii:C', true));
```

> **Platform note**: the `#!asm` block above is 32-bit x86 (Windows) assembly (`esp`-relative args, `ecx`). The `#!C` path is portable, but the assembly snippet is architecture-specific — on Linux/ARM use the C form or rewrite the assembly for the target ABI.

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

---

## Foreign function interface

Fun exposes native functions through a compact **signature-string** convention. Examples drawn from the standard library:

```fun
'kernel32'.getapi('VirtualAlloc', 'iiii:i');  // 4 int args -> int
'tcc'.getapi('tcc_new', 'v:i');               // void arg -> int
```

The signature encodes each argument's type, then `:`, then the return type (`i` = int, `s` = string, `v` = void, `d` = double, etc.). The same mechanism drives COM (`lib-winole`), the Windows API (`lib-winapi`), and the C runtime.

`getapi` is per-platform: `winapi.pas` on 32-bit Windows, and `lffi.pas` - backed by FPC's bundled libffi - on Linux, macOS and win64 (there it resolves against `ffi.dll`).

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
│   ├── lib/           # Standard library (pure Fun, 59 modules)
│   ├── demo/          # Language syntax demos
│   ├── demos/         # Full applications & benchmarks
│   └── key_*.ini      # Keyword alias packs (CN / FR / PUA)
└── LICENSE*           # License files
```

---

## Building

The Fun core is Pascal; the source entry point is `src/prj/fun/funcmd.dpr`.

Toolchain locations for the Windows-hosted `.bat` scripts are centralized in one file: [`src/prj/fun/setenv.bat`](src/prj/fun/setenv.bat). Edit it once to point at your installed Delphi / Free Pascal, or set the `FPC`, `DELPHI2006`, `DELPHI2009` environment variables beforehand — every `make-*.bat` script calls it and picks up the paths.

Each script is `<toolchain>-<target>`; the **build machine** is where it runs, which differs from the target for the cross rows:

| Target                  | Build machine | Script                                    | Toolchain          |
| ----------------------- | ------------- | ----------------------------------------- | ------------------ |
| Windows 32-bit          | Windows       | `src/prj/fun/make-2006.bat` / `-2009.bat` | Delphi 2006 / 2009 |
| Windows 64-bit          | Windows       | `make-win64.bat`                          | FPC cross          |
| Windows CE / ARM        | Windows       | `make-wince.bat`                          | FPC cross          |
| Linux (i386)            | Windows       | `make-linux.bat`                          | FPC 2.4.0 cross    |
| Linux / ARM             | Windows       | `make-arm-linux.bat`                      | FPC cross          |
| Linux x86_64 (native)   | Linux x86_64  | `src/prj/fun/make-linux-x86_64.sh`       | FPC + gcc          |
| Linux aarch64 (arm64)   | Linux x86_64  | `src/prj/fun/make-linux-aarch64.sh`      | FPC cross + Zig    |
| macOS x86_64 / aarch64  | Linux x86_64  | `src/prj/fun/make-darwin.sh`             | FPC cross + Zig    |
| macOS (native)          | macOS         | `src/prj/fun/make-macos.sh`              | FPC (Homebrew)     |

Building with `-DFunDll` produces the embeddable runtime `fun.dll`, which exports the `Run` interface. Build artifacts are covered by `.gitignore` and are not versioned.

The full grammar is defined in [`src/parse/bnf/fun.ebnf`](src/parse/bnf/fun.ebnf).

### Cross builds (macOS and Linux aarch64, from Linux x86_64)

The last two rows are the only builds that need a bootstrapped toolchain. Both
run on a **Linux x86_64 build machine** and produce a native target binary with
no target SDK and no target binutils — the Mach-O and aarch64 assembler/linker
come from the clang/lld bundled with Zig 0.13:

```sh
cd src/prj/fun
./bootstrap-darwin-cross.sh     # once: FPC darwin cross toolchain + Zig (~/.fun/darwin-cross, ~2 GB)
CPU=all ./make-darwin.sh        # -> fun/funcmd-darwin-{x86_64,aarch64}

./bootstrap-linux-aarch64.sh    # once: aarch64-linux RTL, reusing ppcrossa64 + Zig from the darwin tree
./make-linux-aarch64.sh         # -> fun/funcmd-linux-aarch64
```

- **Build machine requirements**: Linux x86_64, host FPC 3.2.x, `make`, `curl` or `wget`, `tar`, and ~2 GB free disk. Zig is fetched by the bootstrap (pinned to 0.13; 0.14 panics on older glibc). No macOS host, Apple SDK, or `osxcross` is required — Zig ships a libSystem stub.
- `bootstrap-linux-aarch64.sh` reuses the `ppcrossa64` and Zig from the darwin toolchain: an FPC compiler binary is CPU-specific but can target any OS it has units for.
- Optional features degrade as usual: no PCRE -> no regex, no libffi unit/stub -> no `getapi` (the win64 CI supplies both, `pcre3.dll` and `ffi.dll`). The Linux aarch64 artifact is the core interpreter (its `-dRegex` and `-dLinuxFFI` need a libc / libffi that are not cross-built yet).
- Porting details: [`art/notes/macos-port.md`](art/notes/macos-port.md).

### Third-party dependencies (not carried in the repo)

To keep the repository small and license-clean, the following third-party
sources/binaries are **not** shipped. If one is missing the build script
**degrades and prints a notice** instead of failing:

| Component | Where to put it | Where to get it | Who builds it |
| --------- | --------------- | --------------- | ------------- |
| PCRE 8 (8-bit) | `src/3rd/pcre-8/` | <https://www.pcre.org/> (8.x source, e.g. 8.45) | Linux: `make-linux-x86_64.sh` compiles it with gcc (static, `-dRegex`); Windows (i386): `src/regex/pcre/make.bat` (Borland bcc32 + make, `-Dpcresrc=<path>`; the objects `pcrd.pas` `{$LINK}`s); win64: the CI builds `pcre3.dll` with MinGW-w64 gcc and links it dynamically (`-dRegex -dPCRE_WinDLL`, see below) |
| Tiny C Compiler 0.9.27 | `src/3rd/tcc/` | the tinycc release on savannah/nongnu, or repo.or.cz tag `release_0_9_27` | `make-linux-x86_64.sh` produces `libtcc.so` (placed next to `funcmd`) |
| libffi (win64) | `ffi.dll` next to `funcmd.exe` | MSYS2 `mingw-w64-x86_64-libffi`, or any x86_64 libffi build | the win64 CI installs it so `getapi` works there (`-dWinFFI`); Linux/macOS use the libffi that ships with FPC |
| Windows runtime DLLs | `fun/libtcc.dll`, `fun/zlib.dll` | official release or build them yourself | no build step; keep them beside `fun.exe` for `ccompile` / `NewJit` |

- Once the directories are in place, `cd src/prj/fun && ./make-linux-x86_64.sh` builds PCRE and TCC automatically.
- Or point at them explicitly: `PCRE_SRC=/path/to/pcre TCC_SRC=/path/to/tcc ./make-linux-x86_64.sh`.
- No PCRE -> the build has no regex (`-dRegex` off); no TCC -> no `libtcc.so`, so `lib-tcc` is unavailable. Neither affects the core interpreter.
- Convenience fetcher: `src/prj/fun/fetch-3rd-party.sh` downloads and unpacks the pinned PCRE 8.45 and TCC 0.9.27 releases into `src/3rd/` (used by CI).

### Regression tests and CI

After building, run the snapshot suite from the repository root:

```sh
fun/test/run-linux-regression.sh     # Linux (or any POSIX host: auto-detects)
fun/test/run-macos-regression.sh     # macOS wrapper; skips the Linux-only tests
fun/test/run-windows-regression.bat  # Windows counterpart
```

The runner is host-aware: `fun/test/regression-skip-<platform>.txt` lists tests
that cannot run on a host (a `/proc` or `libc.so.6` backend, an unported JIT,
...) and `fun/test/expected/<platform>/` can hold host-specific snapshots that
override the shared `fun/test/expected/`. `--update` writes to the host's own
snapshot directory; macOS details and the current skip reasons are in
[`art/notes/macos-port.md`](art/notes/macos-port.md).

[`.github/workflows/regression.yml`](.github/workflows/regression.yml) runs the
suite on five platforms - Linux, macOS and Windows on x64, plus Linux and macOS
on arm64. All five build with Free Pascal and are a gate. The win64 build gets
PCRE from `pcre3.dll`, which the job compiles with the runner's MinGW-w64 gcc
(the bcc32 objects belong to the 32-bit build and MinGW objects cannot be linked
into funcmd, so `pcrd.pas` imports the DLL under `-dPCRE_WinDLL`);
`run-windows-regression.bat` still probes for the engine at startup and reports
the regex-dependent tests as SKIP when a build has none, so a regex-less
toolchain degrades instead of failing.

The same job installs libffi from the runner's MSYS2 and builds win64 with
`-dWinFFI` when the resulting `ffi.dll` sits next to `funcmd.exe`, which is what
turns on `getapi` there: FPC's bundled `ffi` unit already has a WIN64 target, so
the only thing missing on Windows was the library. Both optional features follow
the same rule - if the DLL or the unit is absent the job falls back to the core
interpreter instead of failing, and a probe step reports what the build ended up
with.

`windows-arm64` is disabled: FPC 3.2.2, the pinned toolchain, has no
win64/aarch64 target, so there is nothing to build with.


---

## Standard library

The standard library in [`fun/lib`](fun/lib) is written in pure Fun (59 modules):

> In total roughly 6,000 lines of logical code (excluding comments), about 100 lines per module — all 59 modules written in Fun itself.

- **Data**: `lib-json`, `lib-yaml`, `lib-xml`, `lib-base64`, `lib-cstruct`, `lib-md5`, `lib-crypt`
- **Collections / algorithms**: `lib-set`, `lib-tree`, `lib-stack`, `lib-dyns`, `lib-math`
- **Text**: `lib-string`, `lib-regex`, `lib-match`, `lib-unicode`
- **System / IO**: `lib-file`, `lib-os`, `lib-host`, `lib-time`, `lib-cmdline`, `lib-proc`
- **Network**: `lib-winsock`, `lib-ajax`, `lib-jsonrpc`
- **Databases**: `lib-orm`, `lib-orm-pro`, `lib-orm-gen`, `lib-orm-rpc`, `lib-orm-cte`, `lib-ado`, `lib-ado-schema`
- **Native / low-level**: `lib-winapi`, `lib-winole`, `lib-tcc` (C compile), `lib-jit`, `lib-asm`, `lib-asm-pro`
- **UI**: `lib-ui`, `lib-ui-base`, `lib-dialog`, `lib-trayicon`
- **Concurrency / async**: `lib-async`, `lib-jsasync`, `lib-bind`, `lib-message`

> **Platform-split convention**: the Windows implementation keeps the plain
> module name, and the Unix backend is `<name>-unx.fun` (Linux + macOS); the
> older `<name>-lnx.fun` name is kept as a thin wrapper on top of it. Logic
> shared by both lives in `<name>-base.fun` (not counted above). Backends that
> only work on Linux (e.g. `lib-proc`, which reads `/proc`) stay `<name>-lnx`.
> E.g. `lib-os` / `lib-os-unx` (+ `lib-os-lnx`), and `lib-unicode-base` +
> `lib-unicode` / `lib-unicode-unx`.

---

## Examples

- [`fun/demo`](fun/demo) — syntax demos: functions, closures, currying, classes, objects, sets, regex, and exception handling.
- [`fun/demos`](fun/demos) — full applications and benchmarks: the `notepad--` editor, `odbc-search`, and performance/assembly/JIT benchmarks.

---

## License

Fun is distributed under a **dual-license** model:

1. **Open-source (MIT)** — see [`LICENSE`](LICENSE). You are free to use, modify, and redistribute the source, provided the copyright notice is retained.
2. **Commercial license** (additional terms that apply only to these closed-source redistribution cases):
   - Substantially modifying the kernel and commercially distributing the result closed-source — see [`LICENSE.custom`](LICENSE.custom);
   - Embedding `fun.dll` in a closed-source commercial product or SaaS backend — see [`LICENSE.dll`](LICENSE.dll).

**In short**: internal use, study/research, and releasing modified versions under an open-source license (MIT/GPL etc.) are all free. A commercial license is needed only when you sell a modified kernel or `fun.dll` as a closed-source commercial product. Commercial licenses are one-time, priced per project/company — contact &lt;zwd@funlang.org&gt;.

---

© 2010-2026 Zhang Weidong &lt;zwd@funlang.org>
