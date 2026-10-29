# Changelog

This project records notable changes in the style of [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and follows [Semantic Versioning](https://semver.org/).

**English** (this file) · [简体中文](CHANGELOG.zh.md)

## [Unreleased]

- Fix integer parsing above 2^31: `StrToNum` used a 32-bit `TryStrToInt`
  first, and FPC reports success while wrapping the value
  (`9007199254740991` became `-1`). Numeric literals and JSON/FD numbers now
  keep their value and become `Int64` when they do not fit 32 bits.

- `getJson(json: 2)` now validates numbers against RFC 8259 instead of only
  requiring one digit: `.5`, `03`, `1.`, `1e`, `1e+`, `--1`, `1.2.3` and
  out-of-range integers are rejected with a `strict:` message. Lenient
  `json: true` keeps its historical superset.

- Align the three FD readers (`libfd.inc`, `fd.js`/`fd2.js`, `lib-fd.fun`) and
  the writer: numbers follow the `fd.bnf.fd` grammar (`.5`, `1.`, `+1`,
  `0x10`, `1e` are strings), integers outside JavaScript's safe range stay
  strings, `\xHH` is decoded, `#!kvd:`-style directives are honoured,
  empty documents parse as `[]`, and duplicate named keys are
  last-wins. `lib-fd.fun` also no longer crashes on an absent indentation
  match.

- The JSON writer now encodes C0 control characters as `\u00XX`
  (previously they were replaced with `.`), matching `JSON.stringify`.

## [9.4.9] - 2026-10-28

- Add the `csv` standard-library module: a streaming row-by-row reader and
  writer over any handle with `read`/`write` (such as `fs.open`). Options
  cover `delimiter`, `quote`, `skipEmptyLines` and, for the writer, `crlf`.
  Field counts are strict and blank lines are records unless skipped. The
  standard library is now 73 modules.

- The lexer now tracks whether a shifted `.` is member access, so every
  reserved word is accepted as a member name (`obj.fun`, `obj?.end`), and the
  `bit` prefix no longer leaks into later identifiers. The
  `FunNoSoftKeyword` build switch is gone; the behavior is unconditional.

- Fix an infinite parse loop when `bit` is followed by a reserved word other
  than `and`/`or`/`not`: the internal error token is no longer re-fed, so
  invalid input reports one syntax error and exits.

- `end if`, `end case`, `end loop`, `end do`, `end try`, `end fun` and
  `end class` no longer require a trailing `;`. This is a block-boundary
  exemption only: the `;` before `end` is still required, and an extra
  trailing `;` is still accepted.

## [9.4.8] - 2026-10-27

- Add the `jsonschema` standard-library module for validating JSON/FD data
  against a JSON Schema subset. A schema may be FD (the default authoring
  format), JSON text or an already parsed value. v0 supports `type` (including
  type lists), `properties` / `required` / `additionalProperties`, `items` /
  `minItems` / `maxItems`, numeric bounds, `minLength` / `maxLength` (counted
  in Unicode code points), `pattern` (PCRE), `enum` and `const`. Errors carry a
  JSON Pointer path; unknown keywords are ignored unless `opts.strict` is set.
  `$ref`, composition keywords, tuple `items` and `format` are not supported
  yet.

- Add the `env` module for portable environment variables: `env.get(name,
  default)`, `env.has`, `env.set` and `env.unset`, backed by new `HostEnv*`
  primitives in `lib-host` (case-sensitive on POSIX, case-insensitive on
  Windows).

- Add the `fs` module for directories, recursive listing and walking, temporary
  files and directories, symlink-safe removal and atomic writes. Whole-file
  read/write/append stays on the built-ins. Includes the `fs-demo` example and
  a host-neutral test.

- Document the `logging` module, whose code shipped in 9.4.7 but was missing
  from that release note.

## [9.4.7] - 2026-10-25

- Add a leveled compile-time safe build: `SAFE=strict|readonly|readwrite|custom
  ./make-linux-x86_64.sh` produces the separate `funcmd-safe` binary
  (`-dFunSafe` plus `-dFunSafeAllowRead/Write/Compile`). Strict removes native
  code (`getapi`, `@toCallback`, COM), arbitrary-address memory access, file
  access, and compile-from-file or `inline` loading; readonly allows file
  reads, readwrite also allows writes, and `custom` selects categories with
  `SAFE_ALLOW`. The default `funcmd` and its full regression suite are
  unchanged; a separate `linux-safe` CI job verifies strict and readonly on
  manual dispatch only.

- Add `HttpSession`, cookie-backed server-side sessions (RFC 6265). The cookie
  carries only a random SID; data stays in a store (in-memory by default, or a
  `get`/`set`/`destroy` backend). Options cover `ttl`, `maxAge`, `secure`,
  `sameSite`, `domain`, `path`, and `httpOnly`; `SessionRegenerate` rotates the
  SID after login and `req.session = nil` logs out. Add the
  `http-session-demo` example and tests.

- Add the `lib-path` standard-library module with cross-platform
  `PathClean`, `PathJoin`, `PathDir`, `PathBase`, `PathExt`, `PathIsAbs`,
  `PathToSlash`, and `PathFromSlash`, using `/` on Unix and `\` plus drive
  letters on Windows.

- `uuid` falls back to reading `/dev/urandom` when the Unix libc has no
  `getentropy` (glibc < 2.25), so `UUID()` also works on older Linux hosts;
  it still raises when no OS source is available.

- On Unix, file `size` now uses `stat` instead of opening and seeking the
  file, so it also works for unreadable files.

## [9.4.6] - 2026-10-22

- Add `fun test`, a package test runner. It finds every `*_test.fun` below the
  project root, runs each file in its own child interpreter with the manifest
  dependencies available, prints `PASS`/`FAIL` per file, and exits non-zero
  when any test fails. Tests register blocks with `test('name', { ... })` and
  use the new `test` standard-library module; assertions include `equal`,
  `not_equal`, `is_true`, `is_false`, `match`, `contains`, `greater`, `less`,
  `is_nil`, `not_nil`, `raises`, and `fail`, each with an optional message.
  A project needs `package.fun` but no `bin`; `dist/`, dot-directories, and
  path dependencies are skipped. Add the runnable `fun/demos/test-demo`.

- Add the `uuid` standard-library module. `UUID()` returns an RFC 9562
  version-4 UUID from the OS CSPRNG (`getentropy` on Unix, `RtlGenRandom` on
  Windows), with no seeding, global state, or pseudo-random fallback; it
  raises when the OS source is unavailable.

- Expand `http-server` with URL-decoded query and form access
  (`req.query(k)`, `req.form()`), cookie reading (`req.cookies`,
  `req.cookie(k)`) and writing (`res.cookie`, `res.clearCookie`), and
  multi-value response headers (`res.addHeader`).

- Add HTTP authentication and CORS middleware. `HttpBasicAuth` (RFC 7617)
  and `HttpBearerAuth` (RFC 6750) take a `verify(req, credentials)` hook that
  can return a principal or a custom failure, plus `realm` and `optional`
  options. `HttpCors` handles preflight, origin/method/header policy,
  credentials, exposed headers, max age, and a dynamic `originCheck`. Add the
  `http-cors-demo` and `http-bearer-demo` examples.

- The standard library is now 66 modules, and both READMEs document the
  testing workflow.

## [9.4.5] - 2026-10-20

- Add manifest-driven packages. A project is a directory with a `package.fun`
  manifest: `fun package init [dir] [--bin|--lib]` writes the manifest and a
  runnable template, `fun package add`/`remove` edit only the `dependencies`
  set, and `fun package tidy` installs the exact revisions into the shared
  `~/.fun` cache (`FUN_HOME` overrides it), verifies git tree hashes and
  rewrites the generated `resolved` block. Path dependencies are used in
  place; only git dependencies need `git`.

- Add `fun run [args...]`, which runs the manifest `bin` from the project
  root with its dependencies available. In a directory with `package.fun`, a
  plain `fun <script>` uses the same project-aware launcher, so scripts gain
  the dependency lookup without changing their import paths;
  `FUN_PACKAGE_READY=1` bypasses project mode. Runs are read-only: a missing
  or stale dependency stops with `run 'fun package tidy'` instead of fetching
  anything.

- `fun pack` now defaults to the manifest `bin` when `package.fun` is
  present, resolves paths against the project root, and embeds resolved
  dependencies under `.funpack/packages/<name>/` behind root-level shims, so
  a packed app runs without `~/.fun`.

- Fix bundled console apps dropping their output when stdout is redirected
  (no console detected); `-gui` still suppresses it.

- Document packages in both READMEs and add the runnable
  `fun/demos/package-demo` plus an end-to-end package test in the regression
  suite.

- Have GitHub classify `.fun` scripts as Ada. Linguist has no Fun entry and
  `*.fun` is one of Standard ML's suffixes there, so the repository was
  reported as "Standard ML" and every script was highlighted as SML. Fun's
  syntax is Ada-derived, so `.gitattributes` now sets
  `linguist-language=Ada` on `*.fun`; drop it once Fun is registered with
  linguist.

## [9.4.4] - 2026-10-19

- Add single-file packaging with `fun pack <entry.fun> [-o <out>] [-a <path>]`.
  The output is the interpreter with the project files and declared resources
  appended as a STORE-only zip trailer. On start it extracts them to a temp
  directory and runs the entry through the normal `use`/resource paths, with
  the script arguments shifted by one so `2.arg()` is the first real
  argument. The tool (`fun/lib/tools/fun-pack.fun`) resolves `use` imports,
  honours `-a` files/directories and copies the Windows runtime DLLs next to
  the output. Builds can opt out with `-dFunPack`/`-dFunPackUser`, and
  `FUNPACK=user` produces a consumer-only runtime without the `pack`
  subcommand.

- Add `Netif()`, IPv4 network-interface enumeration on Linux and macOS. It
  returns a set of `[name, ip, family, up, loopback]` entries backed by
  `getifaddrs(3)`; the Windows backend is a follow-up.

- Fix DNS resolution on macOS when a resolver pointer lives above 4 GB:
  `ReadU64` dropped the high bits, so name lookups could fail or return
  garbage.

- Add an opt-in startup profiler (`-dFunStartupTiming`) that reports phase
  timings to stderr. Normal builds are unchanged.

- Drop the RTL `Classes` unit from the interpreter (about 120 KiB smaller on
  the Linux x86_64 build) and rename the generated assembler tables from
  `.fd.2` to `.fd2`, so hosts no longer misclassify them as roff pages in
  language statistics.

## [9.4.3] - 2026-10-18

- Variable declarations with an initializer now use the same parse-time
  assignment specialization as plain assignments. A `var` inside a loop resolves
  its slot once and reuses it instead of repeating the generic assign and
  scope-push chain. On the bundled Linux x86_64 build `var d = i` drops from
  ~57 to ~38 ns/iter, matching a plain assignment in the same scope.

## [9.4.2] - 2026-10-18

- Regex matching no longer recompiles the same pattern on every call. The
  compiled PCRE code is shared through a small LRU cache keyed by pattern text
  and options, with reference counting so a lazy match object always keeps its
  code alive; each regex literal also holds its own reference, so the hot path
  skips the cache lookup. A pattern used a second time is upgraded to PCRE's JIT
  engine; the upgrade is deferred so a one-shot `toRegex()` pays no JIT cost.
  Global `match`/`replace` now write into one growable buffer instead of
  splicing the subject once per match, turning the former O(n^2) replacement
  loop into a single pass. On the bundled Linux x86_64 build, 200 global
  replacements over a ~100 KB subject drop from ~7.3 s to ~0.24 s, repeated
  literal matching improves by ~1.4-1.5x, and a global match by ~3x.
  Replacements without `$` or `\` references skip the per-match replacement
  scan, making literal global replacement another 25-40% faster.

- Global regex replacement now computes `$_` (and the other subject
  references) from the original subject. The old in-place loop rewrote the
  subject between matches, so `'abcabc'.replace(/b/g, '[$_]')` produced
  `a[abcabc]ca[a[abcabc]cabc]c`; it now yields `a[abcabc]ca[abcabc]c`.

- Plain variable assignments are specialized at parse time. The first run
  resolves the target slot once; later runs read simple `CId` sources and write
  the scalar slot directly instead of repeating the virtual assign and scope
  push. On the bundled Linux x86_64 build, `x = i` drops from ~56 to ~38
  ns/iter and a global `gx = i` from ~52 to ~33 ns/iter. Fields, indices,
  self-assignments and scope entries that still need a push keep the generic
  path.

## [9.4.1] - 2026-10-17

- Fix integer comparison of far-apart operands. `varComp` and the CalcOpt fast
  paths for `<`, `>`, `<=`, `>=`, `<>` and `=` computed `a - b` before testing
  the sign; that difference overflows int32 and reversed the result (for
  example `2147483647 > -1` returned false). They now compare the operands
  directly.

## [9.4] - 2026-10-17

- Scalar values stay out of the Variant RTL on the hot paths: comparison and
  logical operators write `varBoolean` results directly, scalar assignment
  fast-paths Boolean/Double as well as Integer, and `CCtwo` no longer builds a
  temporary `CValue` for its left operand. Integer `div`/`mod` gain guarded
  fast paths that still fall through to the RTL for a zero divisor and
  `Low(Integer) div -1`. On the shipped benchmark, `1>2` drops from ~193 to
  ~130 ns/iteration, `if 1>2` from ~166 to ~130 ns, `not 1>2` from ~343 to
  ~196 ns, and `7 div 3` roughly halves.

- The standard library gains an HTTP server and client.
  `fun/lib/http-server.fun` is a single-threaded, platform-neutral server
  (`HttpServer(port)` or `HttpServer('addr:port')`) with literal / `:name` /
  `*` routing (405 with `Allow` on a method mismatch, 404 otherwise), route
  groups and global / group / per-route middleware, parameters and query
  strings, static files, `json` / `text` / `html` responses and an access
  logger, driven by its own poll loop (`run`) or a step at a time
  (`runOnce`). `fun/lib/http-client.fun` is a one-call blocking client,
  `HttpClient(args) -> [rc, code, message, headers, body]`, that sits on the
  host's lib-ajax backend, so the same call works on every platform. The
  server keeps its HTTP framing and keep-alive in `lib-winsock-base.fun` and
  is Linux/macOS only for now: the Windows winsock backend still has no
  RunOnce/Run (its message-pump driver is a follow-up).

- `lib-ajax.fun` (Windows) carries the same `Http(args)` helper as the Unix
  backend, so `HttpClient` no longer falls back to `Ajax`: it forces the
  synchronous transfer, exposes the final response block as `Ajax.headers`
  (lowercased keys, like `lib-ajax-unx`) and returns the same
  `[rc, code, message, headers, body]` set. Together with the earlier
  `HttpServer` -> `HttpServerBase` rename (aliased back to `Server.HTTP` /
  `Server.HTP`, whose second assignment also fixes an `HTP` typo) this closes
  the Windows gaps the server/client work opened.

- `getapi` takes a `variadic: <n>` mark that tells the FFI how many leading
  arguments are fixed, so libffi prepares a variadic call (`ffi_prep_cif_var`,
  falling back to the fixed form if the loaded libffi refuses it). Darwin arm64
  needs this, since a variadic tail is passed on the stack there; the libcurl
  binding's `curl_easy_setopt` uses it, which is what lets the lib-ajax test
  run on macOS.

- `funcmd` says which file it could not find: a missing named script now
  prints `not found: <file>` (still a non-zero exit) instead of failing
  without a word.

- The Delphi build works again. The portability shim in `pcrd`'s dynamic branch
  (`-dPCRE_LINKDLL`) put FPC's `dynlibs` unit in the unit's `uses` clause
  unconditionally, so `dcc32` stopped at
  `pcrd.pas(542) Fatal: F1026 File not found: 'dynlibs.dcu'` even for the static
  build, which never reaches that code - Delphi ships no `dynlibs` unit, FPC
  does. The unit is now imported under `{$IFDEF FPC}` only, and the non-FPC
  side of the branch keeps the same behaviour through the Win32 calls (`HINST`
  handle, `GetProcAddress`, `SafeLoadLibrary`, `FreeLibrary`), so
  `-dPCRE_LINKDLL` remains available to both compilers.

- CI is green on all five platforms (Windows arm64 is disabled: FPC 3.2.2 has
  no win64/aarch64 target). Three Windows-only divergences are fixed, all in
  `{$IfDef FPC}` branches so the Delphi sources stay as they were.
  `ToFunTime` used `VarToDateTime` on every non-Unix build, but FPC's
  `VarToDateTime` goes through `TryStrToDateTime` with the host's
  `ShortDateFormat`/`DateSeparator`, so Fun's ISO time literal
  (`@'2010-04-09 15:35:15'`) raised `EVariantError` ("Invalid variant type
  cast") on a machine with a US locale and took `calc.fun`, `type.fun` and
  `lib-type-test.fun` down at parse time; the FPC build now parses the ISO form
  directly, as the Unix builds already did. Rendering a date back then still
  followed the host locale (`7/18/2010` vs the Unix `18-7-10`), so `funcmd`
  pins `DefaultFormatSettings` to the values FPC uses on Unix (it cannot read
  the locale there without `clocale`), making date and number output
  host-independent. And `Print` wrote through the RTL `Output` text file, which
  FPC tags with `GetConsoleOutputCP()`: every `?.` write was re-encoded from
  the string codepage (CP1252) to the console codepage (CP65001 on the runner),
  doubling every non-ASCII byte. Standard output now goes through a new
  `WriteOut` that writes the raw bytes to the stdout handle on Windows, like
  `WriteErr` already did for stderr, so `set-named.fun` matches again.

- The Windows regression runner probes for the regex engine and reports the
  regex-dependent tests as SKIP while PCRE is absent (a regex literal parses to
  a nil node without `-dRegex`), instead of diffing output that cannot match;
  they run by themselves once a Windows PCRE build exists. The tests that need
  `.getapi` stay skipped even now that the build carries it (`-dWinAPI` is off
  because `winapi.pas` getapi is 32-bit x86 asm, and the others are x86-64
  System V or want a Unix library name), as do the COM ones (`lib-orm-rows`,
  via `lib-xml`), and `lib-file-test`/`lib-dyns-test` (`find()` emits
  `\` on Windows and `/` elsewhere, and the shared snapshots use `/`). The
  workflow's `expected-win` copy is now byte-exact (`ReadAllBytes`); the old
  text-mode copy re-encoded the raw GBK bytes of the `set-named.fun` snapshot
  and made it unmatchable.

- The win64 FPC build has regex now, and links it dynamically. The bcc32 PCRE
  objects belong to the 32-bit build and the MinGW ones cannot be linked into
  funcmd (neither FPC linker resolves their CRT symbols), so the build compiles
  PCRE 8.45 with the runner's MinGW-w64 gcc into `pcre3.dll` beside funcmd.exe,
  and `-dPCRE_WinDLL` swaps the `{$LINK}`ed objects plus the CRT declarations
  for `external 'pcre3.dll'` imports (FPC writes the import table from the DLL
  name alone). Two Pascal-side fixes came with it: the `__llmul` stub is 32-bit
  only (win64 multiplies natively and has no `System.__llmul`), and PCRE memory
  must go back to PCRE's own free - the DLL allocates from its own CRT, so the
  static path's `FreeMem` corrupted the heap right after a match
  (`pcre_free_substring` is `(PUBL(free))(p)`, so the free path uses it). The
  32-bit Delphi build, the static Unix builds and the MinGW search order are
  untouched. The Windows runner's regex probe now finds the engine, so the 8
  regex tests and `portability-probe` run there instead of skipping:
  51/51 checks pass, 41 skipped.

- win64 has `getapi` as well. FPC's bundled `ffi` unit already has a WIN64
  target (`FFI_DEFAULT_ABI = FFI_WIN64`), so the only missing piece was the
  library: the job installs libffi from the runner's MSYS2 and copies it next
  to funcmd.exe as `ffi.dll`, and `-dWinFFI` - mapped onto the existing
  `UnixFFI` symbol, which is what the engine's `getapi`/`@toCallback`
  registration is keyed on - selects the libffi-backed `lffi` unit there.
  `lffi.pas` skips its Unix `{$LINKLIB ffi}` on Windows (FPC writes the import
  table from the `ffi` name in the unit's externals) and appends `.dll` when a
  bare library name does not resolve, so `'kernel32'.getapi(...)` works. If
  libffi or the DLL is missing the job falls back to the core interpreter
  rather than failing, and a new probe step reports regex and getapi
  availability as annotations (a `getapi()` result object is falsy in Fun, so
  the probe calls the function it resolved). Two build details came out of it:
  the unit path has to be passed as one argument - PowerShell's native
  argument passing split a bare `-Fu..\..\lib` into a path plus a stray `lib`
  source file - and `libase.pas` now maps `-dWinFFI` like `host.pas` does, so
  the two files cannot disagree about `UnixFFI` depending on compile order.
  `make-win64.bat` gained the same `-Fu..\..\lib`, so `-dWinFFI` can be used by
  hand once `ffi.dll` is next to funcmd.exe. The 32-bit (Delphi/bcc32) build
  and the Unix paths are untouched.

- The FFI suite runs on win64 too, and it immediately found one more Windows-only
  divergence. Four of its five cases (`ffi-int64`, `ffi-float`, `ffi-float-cb`,
  `ffi-callbacks`) are plain int/double/float/long-long/callback ABI whose output
  is host-independent, so they use the shared snapshots; the job builds the C
  helper with MinGW gcc (`-Wl,--export-all-symbols`, since libffitest.c has no
  `__declspec(dllexport)`), `DyLibWin()` in `lib-host.fun` names it per host, and
  the runner probes for both the DLL and a working `getapi`, adding the cases to
  its skip list when either is missing. `ffi-scalar` stays Unix-only (libc/libm,
  no `getpid` on Windows). The divergence: those cases load `lib-host.fun`, whose
  Windows branch calls `'kernel32'.getapi('GetCommandLine', ':s')` - but kernel32
  exports `GetCommandLineA`/`GetCommandLineW`, the unsuffixed spelling is a header
  macro, and `io.GetProc` (the Delphi path) already retries with the A/W suffix
  while the libffi path did not. Every unsuffixed Windows API name in Fun code was
  therefore unavailable on win64; `lffi.pas` now retries `name + 'A'` there, which
  is also the right variant for the narrow string convention (`nameW` still
  resolves directly). windows-x64 went from 51/51 (skipped 41) to 55/55 (skipped
  37).

- OpenSSL 3 in the crypto tests, and the remaining CI platform fixes.
  `lib-crypt-unx` probed `EVP_PKEY_size`, which OpenSSL 3.0 turned into a header
  macro for `EVP_PKEY_get_size` — the symbol is gone, so the whole probe failed
  on the OpenSSL 3 CI images and took `lib-crypt-lnx` and `lib-e2e-lnx` down with
  it; it now falls back to `EVP_PKEY_get_size`. macOS arm64 installs FPC from
  the Homebrew 3.2.2 bottle instead of the official dmg, whose PackageMaker
  `.mpkg` current macOS refuses with "This package is incompatible with this
  version of macOS" (and which `pkgutil --expand` cannot open); Intel keeps the
  dmg. The Windows build calls `ppcrossx64` directly, as `make-win64.bat` does,
  because the generic `fpc.exe` driver there is the i386 one and forwards
  `-Twin64` to `ppc386.exe`. `lib-asm-a64` is skipped on Linux arm64: its live
  JIT call aborts the interpreter there (`Load()` -> an EFAULT reported as
  `Open "<repo>/" failed`), and its snapshot is x86_64-specific anyway.

- `funcmd` on Windows produced no output when it was run with a script and its
  stdout redirected (a file, a pipe, a CI runner): the GUI/CLI decision used
  `AttachConsole`, which is false without a parent console, so the run was
  mistaken for a GUI launch and `isLog` stayed false even though a script was
  named. A named script now forces command-line mode. The Windows CI job also
  compares against a copy of the shared snapshots with the final newline
  restored: Fun writes CRLF on every platform and the POSIX runner captures with
  `$(...)`, which strips that newline, so a raw Windows redirect was one byte
  longer than every snapshot.

- CI caches the Free Pascal toolchain on every platform (only Linux did). Linux
  already skipped the install on a hit; the Windows job now caches `C:\FPC` and
  skips both installers the same way. macOS caches the artefacts, not the
  install: Intel caches the 274 MB dmg and arm64 the Homebrew downloads, so
  those two no longer re-download (they still run the package install, which
  writes to system paths such as `/usr/local` and cannot be cached directly).

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
  (Linux, macOS and Windows, x64 + arm64; the Windows build was a bring-up
  first pass at the time - all jobs gate the build now, see the latest entry).
  Fixes from the Issue #2 macOS
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
