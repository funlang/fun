# Changelog

This project records notable changes in the style of [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and follows [Semantic Versioning](https://semver.org/).

**English** (this file) · [简体中文](CHANGELOG.zh.md)

## [Unreleased]

- OpenSSL 3 in the crypto tests, and the remaining CI platform fixes.
  `lib-crypt-unx` probed `EVP_PKEY_size`, which OpenSSL 3.0 turned into a header
  macro for `EVP_PKEY_get_size` — the symbol is gone, so the whole probe failed
  on the OpenSSL 3 CI images and took `lib-crypt-lnx` and `lib-e2e-lnx` down with
  it; it now falls back to `EVP_PKEY_get_size`. The macOS FPC install retries
  with the package's `Distribution` os-version guard stripped when a newer macOS
  rejects the 3.2.2 `.pkg` with "This package is incompatible with this version
  of macOS". The Windows FPC install selects every component (`/TYPE=full`), adds
  the win64 cross package when the combined installer leaves only
  `bin\i386-win32`, and puts the win64 compiler first on `PATH`. `lib-asm-a64`
  is skipped on Linux arm64: its live JIT call aborts the interpreter there
  (`Load()` -> an EFAULT reported as `Open "<repo>/" failed`), and its snapshot
  is x86_64-specific anyway.

- Fix the first CI build of a fresh checkout. A pristine PCRE tarball ships
  only `config.h.generic` / `pcre.h.generic` / `pcre_chartables.c.dist` (the
  upstream `./configure` output is byte-identical) and has no
  dftables-generated `pcre_default_tables.c`, so `make-linux-x86_64.sh` and
  `make-macos.sh` aborted immediately on the runners. Both now create the
  build-ready files from the shipped copies and skip the optional generated
  duplicate. Also drop the absolute repo path from `lib-loadcheck.sh`'s FAIL
  lines so its snapshot is host-independent.

- Portable regression harness and macOS CI. `fun/test/run-linux-regression.sh`
  now detects the host (linux / macos) and reads
  `fun/test/regression-skip-<platform>.txt` plus an optional
  `fun/test/expected/<platform>/` snapshot override, so tests that are
  Linux-only by design (libc.so.6 / `/proc` / x86-64 assembly / TCC / JIT) are
  reported as SKIP instead of failing on macOS, while the `ffi-*.fun` suite was
  made host-aware (`LibC()`/`DyLib()`, and `libffitest` built as `.dylib`) so
  getapi is exercised on macOS too. Added
  `fun/test/run-macos-regression.sh`, `regression-skip-macos.txt`, a native
  macOS build script `src/prj/fun/make-macos.sh`, a third-party source fetcher
  `src/prj/fun/fetch-3rd-party.sh`, `fun/test/ffi/build.sh` (builds the FFI
  helper on demand; it is not tracked), and `.github/workflows/regression.yml`
  (six jobs: Linux, macOS and Windows, x64 + arm64). The Linux/macOS jobs build
  natively and gate the build; the Windows jobs are a bring-up first pass and
  are marked continue-on-error (the Windows build has no regex yet and FPC
  3.2.2 has no win64/aarch64 target). Fixes from the Issue #2 macOS
  real-machine report: `find()` now emits directory entries in a stable byte
  order (ext4, APFS and NTFS enumerate differently, so the `lib-dyns-test` /
  `lib-file-test` snapshots were host-specific); `run-benchmarks.sh` no longer
  requires GNU `timeout` (absent from a stock macOS userland); `lib-loadcheck.sh`
  byte-orders its module glob; the `builtin-dispatch` and `lib-host-test`
  snapshots are now host-neutral; and the allocation-dependent "huge list index
  raises" assertion in `lib-bounds-test` was dropped (it raises `EOutOfMemory`
  on Linux but can succeed lazily on macOS; see `safety-bounds.md`). Linux
  regression stays 92/92.

- Linux aarch64 (arm64) cross build of the interpreter, kept alongside the
  x86_64 one. `bootstrap-linux-aarch64.sh` builds the aarch64-linux FPC
  RTL/rtl-objpas/hash units on an x86_64 host (reusing the darwin toolchain's
  `ppcrossa64`), and `make-linux-aarch64.sh` produces
  `fun/funcmd-linux-aarch64` (static, syscall-based, stripped). Assembly and
  linking go through `src/prj/fun/linux-aarch64/{as,ld}` (Zig clang/lld), so no
  aarch64 binutils or glibc is required. Not enabled yet: `-dRegex` (needs a
  libc) and `getapi`/`-dLinuxFFI` (needs an aarch64 libffi).
- Interpreter CLI: running with no script file now prints the usage and exits
  0. Previously it tried to run the executable itself as a script, which only
  reported `syntax error[ELF]` from the ELF/PE/Mach-O header and exited 1. A
  named-but-missing script is still a non-zero error, and the
  `<exe>.fun`-next-to-the-binary fallback still runs. The usage line now prints
  `fun` instead of `fun.exe` on non-Windows hosts.
- macOS cross-build binaries shrink ~67%. FPC's Darwin target asks ld64 to
  `-dead_strip` and to strip (`-x`, from `-Xs`), but the `darwin/ld` shim used to
  drop both, and Apple's separate `strip` step cannot run on Linux either - so
  the linked Mach-O kept a full symbol table (__LINKEDIT ~1.4 MB, 38k symbols).
  The shim now forwards them to lld (`-Wl,-dead_strip`, and `-Wl,-s` for the
  strip request), giving `funcmd-darwin-x86_64` 2.62 MB -> 858 KB and
  `funcmd-darwin-aarch64` 2.69 MB -> 939 KB, with the arm64 ad-hoc signature
  still valid.
- macOS Fun-level library port (engine FFI + `-unx` backends). `getapi` now works
  on Darwin: `-dLinuxFFI` is generalised to one `UnixFFI` symbol (macOS builds
  pass `-dDarwinFFI`), `bootstrap-darwin-cross.sh` builds FPC's bundled `ffi`
  unit for both darwin CPUs and seeds the `libffi.tbd` linker stub from
  `DARWIN_SDK`, so `make-darwin.sh` links `/usr/lib/libffi.dylib` (verified in
  both Mach-O binaries). On the Fun side, the backends that differed *only* by
  library name became `lib-*-unx.fun` (Linux + macOS) with `lib-*-lnx.fun` kept
  as thin `use` wrappers: os, cmdline, unicode, ado, ado-schema, xml, crypt,
  ajax, winsock, jsonrpc and orm-rpc. `lib-host.fun` gained `IsMac()`/`IsUnix()`
  and the library-name helpers `LibC()` (`libc.so.6` vs `libSystem.B.dylib`),
  `DyLib()` and `DyLibList()`. Darwin-specific fixes: `.dylib` library names,
  `proc_pidpath` for `GetProcName`, the 256-byte `struct utsname` layout, the
  Darwin `sockaddr_in` (8-bit `sin_len`/`sin_family`) and socket-option values,
  `__error` (not glibc's `__errno_location`) and the Darwin `addrinfo`
  `ai_addr` offset. `lib-zlib` and `lib-tcc` gained macOS library names. Still
  Linux-only: `lib-proc` (needs sysctl/libproc) and `lib-asm` (JIT / executable
  memory; needs `MAP_JIT` on Apple Silicon). Runtime correctness on macOS is
  unverified here (no macOS host); Linux regression stays 91/91.
- macOS (Darwin) cross build. `src/prj/fun/bootstrap-darwin-cross.sh` assembles an
  FPC 3.2.2 cross toolchain (x86_64-darwin and aarch64-darwin) on Linux, and
  `src/prj/fun/make-darwin.sh` produces `fun/funcmd-darwin-<cpu>`. Mach-O assembly
  and linking go through two shims (`src/prj/fun/darwin/{clang,ld}`) over the
  clang/lld bundled with Zig 0.13, so no macOS SDK is required. On the engine
  side the `{$IfDef Linux}` guards that only meant "not Windows" were generalised
  to FPC's built-in `UNIX` (identical on Linux, now also true on Darwin),
  `'host'.arg()` reports `os macos`, and the vendored PCRE externals take `cdecl`
  on Darwin so the Mach-O leading underscore is emitted. That step was a
  compile/link milestone only; the Fun-level backends and the `getapi` FFI were
  added in the entry above (see `art/notes/macos-port.md`).
- Hand-written assembly gains an AArch64 (ARM64) backend. `lib-asm-a64.fun`,
  with its own table `asm-list-a64.fd` built by the same
  `fun/lib/tools/make-asm-list.fun` chain, emits the fixed-width,
  bit-field-encoded aarch64 instruction set: add/sub (immediate and shifted
  register), logical (register and immediate, with a bitmask-immediate
  encoder), move wide, `mov` aliases, `csel`, loads/stores (unsigned offset,
  pre/post index, register offset, and `stp`/`ldp` pairs), branches and `ret`.
  Local labels and `B`/`BL`/`B.cond` offsets are resolved in two passes; `mov`
  immediates pick movz/movn/orr/movk like the assembler. The backend is
  opt-in (`Assembly = AssemblyA64();`) and refuses to run on a non-aarch64
  cpu.
- Instruction-cache coherency on aarch64: `lib-asm.fun` calls an optional
  `_asm_flush(ptr, len)` hook after copying code into executable memory, and
  `lib-asm-a64.fun` binds libc's `__clear_cache` (falling back to
  `cacheflush`, then libgcc) to it - without it the cpu may execute stale
  bytes, a fault that only shows up on aarch64.
- `lib-asm.fun` grew the hooks both backends share: an overridable `ret_hex`
  return tail (x86 `C3`, aarch64 `C0035FD6`), the moved-down
  `_ptr2hex`/`int2hex64`/`<name>` callback resolver, and a per-backend `arch`
  checked by `Load()`. A backend can no longer silently execute foreign
  machine code (previously aarch64 ran x86 bytes into SIGILL).
- `'host'.arg()` now reports `cpu arch64` on AArch64 (the `CPUARCH64` branch
  was misspelt, so it fell through to `cpu64`); the assembler cpu gate keys on
  this value.
- Tests: `fun/test/lib-asm-a64.fun` snapshots the encoder (its encodings were
  cross-checked byte-for-byte against the keystone/gas assembler), and
  `fun/test/tools/asm-a64-diff.sh` re-runs that differential against a
  `gcc-aarch64-linux-gnu` toolchain when one is installed. The Linux
  regression list includes the a64 case.
- Version probing: the runtime version now lives in a generated include,
  `src/core/version.inc` (`funVersion`, numeric YYYYMMDD; `funRelease`, the
  curated language version string), pulled into `fun.pas` with `{$I}`. It is
  regenerated by a pure-Fun script, `fun src/prj/fun/gen-version.fun [YYYYMMDD]
  ["release"]` - no shell and no git, so the same command works on Windows and
  Linux. The stamp defaults to the day you run it (pass an explicit date for a
  reproducible release). A script can probe the running interpreter two ways
  that read the same constant: `N.time()` (returns `funVersion` for N in
  2010..2099) and the new `version` field of `'host'.arg()`. Previously the
  number was a hardcoded literal inside `_time` and `'host'.arg()` exposed only
  the readable `fun` string. `lib-host-test.fun` asserts the two paths agree.
- First open-source release of the Fun core and standard library source.
- The command-line `funcmd` now writes diagnostics to stderr and exits non-zero
  (1) on a parse or runtime error, so `a.fun && b.fun`, CI jobs and cron alarms
  no longer mistake a failed script for success. Runtime errors are prefixed
  with `file:line:`. A function traceback (one `  in name() (file:line)` line per
  frame, innermost first, capped at 10) is appended only in builds that define
  `-dFunTraceback`; the default build reports the failing command alone, so it
  pays nothing per call. Normal script output (`?.`) stays on stdout. The
  embedded `fun.dll` `Run` return-code contract is unchanged, and
  `-gui`/non-console runs stay silent as before. Diagnostics go through the OS
  standard-error handle (not the RTL `StdErr`/`ErrOutput` text file, which
  Delphi 7 does not declare), so the driver builds unchanged on Delphi 7 and
  Free Pascal.
- Treat end of input as an implicit statement terminator: a final statement
  written without its trailing `;` is now parsed and executed instead of being
  silently dropped. The lexer previously emitted no token at end of input, so
  the pending statement never reduced and the script exited 0 with no output
  (for example, a program whose last line is `?. x` printed nothing). Only the
  end of input is affected; a missing `;` between statements is still a syntax
  error. The change lives in the lexer runtime (`src/parse/lib/lexlib.pas`) and
  touches no generated parse/lex tables.
- Added `README.md`, `CONTRIBUTING.md`, `.gitignore`, `.gitattributes`.
- Hardened string/list indexing and byte access against out-of-bounds memory
  access: out-of-range writes now raise, out-of-range reads yield a safe default
  (`s[i]`, `.toByte`, `.fromByte`, `.toNum(ptr:)`, `.movs`, `.x`, `.toStr`,
  list `@count`). String assignment keeps its reference semantics.
- Language version: 9.0.
- Bound JSON/FD nesting depth when parsing. The scanners are iterative, but the
  resulting tree is released, cloned and serialized recursively, so an
  attacker-supplied document with thousands of `[`/`{` levels could overflow the
  stack and crash the process (DoS). Nesting deeper than 512 levels now raises
  instead of building an unusable tree.
- Fix multi-row `DObject.Get`: the nested `Read` helper shadowed the `args`
  member, so fetching more than one row raised `@Fields not found`. The row loop
  now reads `this.args`.
- Added console input builtins in `libase.pas`: `'line'.input([prompt])`,
  `'char'.input([prompt])` (a single keypress in raw mode on a terminal) and
  `'all'.input([prompt])`. An optional second argument receives an `ok` flag
  that reports end of input; because Fun treats `''` and nil as equal, that flag
  is the only reliable way to stop a read loop that may see blank lines. Linux
  reads standard input byte by byte and supports all three modes; on Windows
  the builtin only reads lines, through the RTL `ReadLn`, so the text comes
  back in the build's string encoding (ANSI, or Unicode on Delphi 2009) and a
  multi-byte character is never split into bytes.
- Added strict comparison and a type id for basic values: `a.eq(b)` is true only
  when the type and the value both match (`nil`/`0`/`''`/`false` are distinct,
  `'1' <> 1`, `1 <> 1.0`, string compare is case-sensitive), and `a.type()`
  returns a portable logical type id. The ids are anchored to COM `VARENUM`
  (`VT_*`, the table behind Delphi's `VType` and ADO's `DataTypeEnum`) and
  normalize the runtime's platform-dependent tags: every integer width -> 3,
  every float width -> 5, every string form -> 8. Both live in `libase`, apply
  to basic (non-object) values, and leave the loose `=` unchanged; `100+` is
  reserved for Fun-only object kinds.
- Added key probing for collections: `s.@has(key)` is true when a list or set
  has that key, even when the stored value is nil. `m[key]` cannot tell a
  missing key from a nil value (both read as nil), and `key in m` scans values
  instead of keys, so this is the only way to ask whether a key is present. A
  numeric key (or an all-digit string, matching how `m[key]` resolves) addresses
  a list slot; any other key names a set member. It sits in `libset` beside the
  other native collection methods (`@count`, `@each`, `@add`).
- Filled in standard-library built-in method docs that had gone unlisted:
  `x.input(prompt, ok)` in `lib-file`, `a.eq(b)` / `a.type()` in `lib-type`
  (synced from the local tree where they had been added by hand), and `n.arg()`
  / `'host'.arg()` / `'defaultCodePage'.set(cp)` in `lib-host`. Comment-only,
  no behavior change.
- Fixed asymmetric Boolean vs number comparison under Free Pascal: the generic
  variant compare coerced its operands by order, so `true = 1` was false while
  `1 = true` was true (same for `<`/`>`, `<=`/`>=`, `<>`). `varComp` now coerces
  a Boolean and a number to a common numeric type with `true` = -1
  (`VARIANT_BOOL`, matching Delphi/COM `VarCmp`), so both operand orders agree.
  The branch is FPC-only (`{$IfDef FPC}`); Delphi's `VarCmp` was already
  symmetric. Covered by fun/test/bool-num-cmp.fun (local suite: 89/89).
- `str.getJson(json: 2)` now enforces RFC 8259 separator grammar, not just the
  unclosed / bracket-imbalance / trailing-value cases. One separator state
  machine replaces the old "after ':'" flag: trailing commas (`{"a":1,}`),
  leading or doubled commas (`[,1]`, `[1,,2]`), missing commas (`[1 2]`,
  `{"a":1 "b":2}`), a missing or doubled colon (`{"a" 1}`, `{"a"::1}`),
  `;`/`=` separators, single-quote / backtick strings, `@` date literals, hex
  numbers (`0xff`), `nil`, and non-string object keys (`{a:1}`, `{1:2}`,
  `{[1]:2}`) are all rejected. Closing brackets are matched against the open
  container (`[1,2}`, `{"a":1]`), a completed top-level value rejects any
  trailing input (`{"a":1} 2`, `[1,2] "x"`), and an empty or whitespace-only
  document raises `no JSON value`. A bare scalar is now a legal root (`20`,
  `"hi"`, `true`, `null`), which strict mode previously rejected by mistake.
  Strict strings reject raw control characters and validate escapes (`\uXXXX`
  needs four hex digits; surrogates need not pair). Numbers stay lenient by
  design - `.5`, `03` and `1.` are still accepted, because real-world JSON
  carries them (a number token with no digit at all, such as a lone `.` or `-`,
  is rejected) - while lenient `json:true` and FD parsing are byte-for-byte
  unchanged.

## [9.0] - 2026

- Data-centric scripting: built-in JSON and FD data formats, native list / set / tree collections, bundled PCRE regex.
- Interpreter core (value model / objects / control flow), built-in runtime library, and 58 standard-library modules.
- Dual build: command-line `funcmd` and embeddable runtime `fun.dll`.
- Delphi 2006/2009 and Free Pascal cross-platform builds (Windows / Linux / ARM / WinCE).
- Companion IDE (`funide`) and example applications (`notepad--`, `odbc-search`, benchmarks).
- Runtime C compilation (TCC), JIT, and inline assembly via the standard library.

> Note: this repository has a long pre-release history (back to 2010) that was not carried over into the open-source commits, so the changelog begins at the first open-source release.
