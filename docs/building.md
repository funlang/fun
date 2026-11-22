# Building Fun

The Fun core is Pascal; the source entry point is `src/prj/fun/funcmd.dpr`.
This guide covers native builds, cross builds, optional dependencies, safe
builds and the regression/CI setup. For the short version, see the README.

## Contents

- [Toolchains and build scripts](#toolchains-and-build-scripts)
- [Native builds](#native-builds)
- [Platform capability matrix](#platform-capability-matrix)
- [Cross builds](#cross-builds)
- [Third-party dependencies](#third-party-dependencies)
- [Safe builds](#safe-builds)
- [Regression tests and CI](#regression-tests-and-ci)

---

## Toolchains and build scripts

Toolchain locations for the Windows-hosted `.bat` scripts are centralized in
[`src/prj/fun/setenv.bat`](../src/prj/fun/setenv.bat). Edit it once to point at
your installed Delphi / Free Pascal, or set the `FPC`, `DELPHI2006`,
`DELPHI2009` environment variables beforehand — every `make-*.bat` script calls
it and picks up the paths.

Each script is `<toolchain>-<target>`; the **build machine** is where it runs,
which differs from the target for the cross rows:

| Target                  | Build machine | Script                                    | Toolchain          |
| ----------------------- | ------------- | ----------------------------------------- | ------------------ |
| Windows 32-bit          | Windows       | `src/prj/fun/make-2006.bat` / `-2009.bat` | Delphi 2006 / 2009 |
| Windows 64-bit          | Windows       | `make-win64.bat`                          | FPC cross          |
| Windows arm64 (bring-up) | Linux x86_64  | `src/prj/fun/make-win-arm64.sh`           | FPC 3.3.1 cross + Zig |
| Windows CE / ARM        | Windows       | `make-wince.bat`                          | FPC cross          |
| Linux (i386)            | Windows       | `make-linux.bat`                          | FPC 2.4.0 cross    |
| Linux / ARM             | Windows       | `make-arm-linux.bat`                      | FPC cross          |
| Linux x86_64 (native)   | Linux x86_64  | `src/prj/fun/make-linux-x86_64.sh`        | FPC + gcc          |
| Linux aarch64 (arm64)   | Linux x86_64  | `src/prj/fun/make-linux-aarch64.sh`       | FPC cross + Zig    |
| Linux LoongArch64       | Linux x86_64  | `src/prj/fun/make-linux-loongarch64.sh`   | FPC main cross     |
| Linux riscv64           | Linux x86_64  | `src/prj/fun/make-linux-riscv64.sh`       | FPC main cross     |
| macOS x86_64 / aarch64  | Linux x86_64  | `src/prj/fun/make-darwin.sh`              | FPC cross + Zig    |
| macOS (native)          | macOS         | `src/prj/fun/make-macos.sh`               | FPC (Homebrew)     |

Building with `-DFunDll` produces the embeddable runtime `fun.dll`, which
exports the `Run` interface. Build artifacts are covered by `.gitignore` and
are not versioned.

The full grammar is defined in
[`src/parse/bnf/fun.ebnf`](../src/parse/bnf/fun.ebnf).

## Native builds

The common native paths are:

```sh
# Linux x86_64 (compiles PCRE and TCC when present)
cd src/prj/fun
./make-linux-x86_64.sh

# macOS (Homebrew FPC)
cd src/prj/fun
./make-macos.sh
```

```bat
REM Windows x64
cd src\prj\fun
make-win64.bat
```

The Linux script also probes for FPC's `libffi` unit under both `lib/` and
`lib64/`, so `getapi`/FFI turns on automatically on Fedora/RHEL-style layouts.

## Platform capability matrix

Three capability layers (regex, FFI, runtime C) plus the machine-code layer,
a second build mode for untrusted scripts, and an opt-in worker build:

| Platform       | regex | FFI | runtime C (tcc) | asm | safe build | worker build |
| -------------- | ----- | --- | --------------- | --- | ---------- | ------------ |
| linux-arm64    | yes   | yes | yes             | yes | yes        | yes          |
| linux-loongarch64 | yes | yes | no             | yes | yes        | yes          |
| linux-riscv64  | yes   | yes | no              | yes | yes        | yes          |
| linux-x64      | yes   | yes | yes             | yes | yes        | yes          |
| macos-arm64    | yes   | yes | yes             | yes | yes        | yes          |
| macos-x64      | yes   | yes | yes             | yes | yes        | yes          |
| win-x64        | yes   | yes | yes             | yes | yes        | yes          |

`safe build` is the separate `fun-safe` binary (`-dFunSafe`, strict level); it
ships next to the default interpreter, so the default build and its behaviour
are unchanged. `worker build` is the opt-in `fun-mt` binary described in
[`worker-model.md`](../fun/lib/worker-model.md). Every other column describes
the default binary. `runtime C` is now available on both macOS architectures
through `libtcc.dylib`. Apple Silicon uses a small TCC patch for the Darwin
ucontext fields and `MAP_JIT` handling. The release notes and each archive's
`capabilities.json` are generated from probes, so a degraded build cannot claim
a capability it does not have.

Windows arm64 is bring-up only (an FPC codegen crash blocks release), and the
Win32/Windows CE builds are legacy; none of them is a release gate. See
[`ROADMAP.md`](../ROADMAP.md) for their current status.

## Cross builds

The macOS, Linux aarch64, LoongArch64 and riscv64 rows are the builds that need
a bootstrapped toolchain. They all run on a **Linux x86_64 build machine** and
produce a native target binary; the macOS/aarch64 assembler and linker come
from the clang/lld bundled with Zig 0.13, while LoongArch64 and riscv64 use GNU
binutils (`binutils-loongarch64-linux-gnu`, `binutils-riscv64-linux-gnu`):

```sh
cd src/prj/fun
./bootstrap-darwin-cross.sh     # once: FPC darwin cross toolchain + Zig (~/.fun/darwin-cross, ~2 GB)
CPU=all ./make-darwin.sh        # -> fun/funcmd-darwin-{x86_64,aarch64}
CPU=all FUN_THREADS=1 ./make-darwin.sh  # -> fun/funcmd-darwin-{x86_64,aarch64}-mt

./bootstrap-linux-aarch64.sh    # once: aarch64-linux RTL, reusing ppcrossa64 + Zig from the darwin tree
./make-linux-aarch64.sh         # -> fun/funcmd-linux-aarch64

# LoongArch64 is prerelease-only: FPC has no stable loongarch64 target yet.
./bootstrap-linux-loongarch64.sh  # once: FPC main cross compiler + loongarch64 binutils
./prepare-linux-loongarch64-sysroot.sh  # once: Alpine musl/FFI/PCRE sysroot
FULL=1 ./make-linux-loongarch64.sh      # -> fun/funcmd-linux-loongarch64-musl
FUN_THREADS=1 FULL=1 ./make-linux-loongarch64.sh  # -> ...-musl-mt

# riscv64 is also prerelease-only: FPC's backend is still on main.
./bootstrap-linux-riscv64.sh  # once: FPC main cross compiler + riscv64 binutils
./prepare-linux-riscv64-sysroot.sh  # once: Alpine musl/FFI/PCRE sysroot
FULL=1 ./make-linux-riscv64.sh      # -> fun/funcmd-linux-riscv64-musl
FUN_THREADS=1 FULL=1 ./make-linux-riscv64.sh  # -> ...-musl-mt
```

- **Build machine requirements**: Linux x86_64, host FPC 3.2.x, `make`, `curl`
  or `wget`, `tar`, and ~2 GB free disk. Zig is fetched by the bootstrap
  (pinned to 0.13; 0.14 panics on older glibc). No macOS host, Apple SDK, or
  `osxcross` is required — Zig ships a libSystem stub.
- `bootstrap-linux-aarch64.sh` reuses the `ppcrossa64` and Zig from the darwin
  toolchain: an FPC compiler binary is CPU-specific but can target any OS it
  has units for.
- The LoongArch64 path needs `binutils-loongarch64-linux-gnu` 2.42 or newer and
  an FPC main snapshot. It cross-builds against an Alpine musl sysroot, so
  regex, FFI and the `-lnx` backends are available, as is
  `lib-asm-loongarch64` (the sysroot ships `libgcc_s` for `__clear_cache`);
  TinyCC is not. `.github/workflows/loongarch.yml` runs this build on pushes to
  main, builds the `-mt` worker binary, runs `lib-worker-test` under qemu, and
  uploads the stage used by nightly prereleases.
- The riscv64 path needs `binutils-riscv64-linux-gnu` and an FPC main snapshot,
  and uses the same Alpine musl sysroot approach, so regex, FFI, the `-lnx`
  backends and `lib-asm-riscv64` are available (the sysroot ships `libgcc_s` for
  `__clear_cache`); TinyCC is not. `.github/workflows/riscv64.yml` runs this
  build on pushes to main, builds the `-mt` worker binary, runs
  `lib-worker-test` under qemu, and uploads the stage used by nightly
  prereleases; `fun/test/run-riscv64-qemu.sh` runs the same Linux suite under
  `qemu-riscv64`.
- Optional features degrade as usual: no PCRE -> no regex, no libffi unit/stub
  -> no `getapi` (the win64 CI supplies both, `pcre3.dll` and `ffi.dll`). The
  cross-built Linux aarch64 artifact is the core interpreter (its `-dRegex` and
  `-dLinuxFFI` need a libc / libffi that are not cross-built yet); a native
  Linux arm64 build, as in CI, has both.
- Porting details: [`art/notes/macos-port.md`](../art/notes/macos-port.md).

## Third-party dependencies

To keep the repository small and license-clean, the following third-party
sources/binaries are **not** shipped. If one is missing the build script
**degrades and prints a notice** instead of failing:

| Component | Where to put it | Where to get it | Who builds it |
| --------- | --------------- | --------------- | ------------- |
| PCRE 8 (8-bit) | `src/3rd/pcre-8/` | <https://www.pcre.org/> (8.x source, e.g. 8.45) | Linux: `make-linux-x86_64.sh` compiles it with gcc (static, `-dRegex`); Windows (i386): `src/regex/pcre/make.bat` (Borland bcc32 + make, `-Dpcresrc=<path>`; the objects `pcrd.pas` `{$LINK}`s); win64: the CI builds `pcre3.dll` with MinGW-w64 gcc and links it dynamically (`-dRegex -dPCRE_WinDLL`, see below) |
| Tiny C Compiler 0.9.27 | `src/3rd/tcc/` | the tinycc release on savannah/nongnu, or repo.or.cz tag `release_0_9_27` | `make-linux-x86_64.sh` produces `libtcc.so`; `build-win64-deps.sh` produces the x86-64 `libtcc.dll` (win64); `build-tcc-darwin.sh` produces `libtcc.dylib` (macOS x86_64 and arm64, the latter with `patches/tcc-darwin-arm64.patch`) |
| libffi (win64) | `ffi.dll` next to `funcmd.exe` | MSYS2 `mingw-w64-x86_64-libffi`, or any x86_64 libffi build | the win64 CI installs it so `getapi` works there (`-dWinFFI`); Linux/macOS use the libffi that ships with FPC |
| zlib 1.2.11 (win64) | `src/3rd/zlib-1.2.11/` | <https://zlib.net/fossils/> | `build-win64-deps.sh` produces the x86-64 `zlib.dll`; Linux/macOS use the system zlib |

- Once the directories are in place, `cd src/prj/fun && ./make-linux-x86_64.sh`
  builds PCRE and TCC automatically.
- Or point at them explicitly:
  `PCRE_SRC=/path/to/pcre TCC_SRC=/path/to/tcc ./make-linux-x86_64.sh`.
- No PCRE -> the build has no regex (`-dRegex` off); no TCC -> no `libtcc.so`,
  so `lib-tcc` is unavailable. Neither affects the core interpreter.
- Convenience fetcher: `src/prj/fun/fetch-3rd-party.sh` downloads and unpacks
  the pinned PCRE 8.45 and TCC 0.9.27 releases into `src/3rd/` (used by CI).

## Safe builds

For untrusted scripts, build the separate capability-restricted interpreter:

```sh
cd src/prj/fun && SAFE=strict ./make-linux-x86_64.sh   # produces funcmd-safe
fun/test/run-safe-regression.sh strict                  # focused capability tests

# Windows
cd src\prj\fun && set SAFE=strict && make-win64.bat      # produces funcmd-safe.exe
fun\test\run-safe-regression.bat strict
```

`funcmd-safe` (`-dFunSafe`) removes native code (`getapi` / `@toCallback` /
COM), arbitrary-address memory access, file access, and compile-from-file or
`inline` code loading at compile time. Pick the level in the build script:
`SAFE=strict` blocks all of them, `SAFE=readonly` allows file reads,
`SAFE=readwrite` also allows writes, and `SAFE=custom
SAFE_ALLOW=read,write,compile` selects categories explicitly. The default
`funcmd` and its full regression suite are unchanged. Every release also ships
the strict build; a separate `linux-safe` CI job verifies strict and readonly,
and the Windows job builds and runs the same strict capability test. The
`linux-safe` job only runs on manual dispatch (`safe_only`), not on push/PR.

## Regression tests and CI

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
[`art/notes/macos-port.md`](../art/notes/macos-port.md).

[`.github/workflows/regression.yml`](../.github/workflows/regression.yml) runs
the suite on five platforms - Linux, macOS and Windows on x64, plus Linux and
macOS on arm64. All five build with Free Pascal and are a gate. The win64 build
gets PCRE from `pcre3.dll`, which the job compiles with the runner's MinGW-w64
gcc (the bcc32 objects belong to the 32-bit build and MinGW objects cannot be
linked into funcmd, so `pcrd.pas` imports the DLL under `-dPCRE_WinDLL`);
`run-windows-regression.bat` still probes for the engine at startup and reports
the regex-dependent tests as SKIP when a build has none, so a regex-less
toolchain degrades instead of failing.

The `linux-x64`, `linux-arm64`, `macos-x64` and `macos-arm64` jobs also build
`funcmd-mt` (`FUN_THREADS=1`) and run the focused `lib-worker-test` suite; the
Windows job builds `funcmd-mt.exe` and runs the same test. This stays in the
existing jobs rather than a separate workflow: the compiler and third-party
caches are already present, and a second runner would pay checkout and
toolchain startup for a roughly one second compile. Only the MT binary has its
own cache entry, so platforms without workers keep their existing `funcmd`
cache.

The same job installs libffi from the runner's MSYS2 and builds win64 with
`-dWinFFI` when the resulting `ffi.dll` sits next to `funcmd.exe`, which is what
turns on `getapi` there: FPC's bundled `ffi` unit already has a WIN64 target, so
the only thing missing on Windows was the library. Both optional features follow
the same rule - if the DLL or the unit is absent the job falls back to the core
interpreter instead of failing, and a probe step reports what the build ended up
with.

With `getapi` in place, the Windows job also builds the FFI test helper
(`fun/test/ffi/libffitest.c`) into `libffitest.dll` with the same MinGW gcc and
runs the four host-independent FFI cases (`ffi-int64`, `ffi-float`,
`ffi-float-cb`, `ffi-callbacks`) against the shared snapshots, so 64-bit
integers, float/mixed arguments and `@toCallback` closures are covered on win64
too; `ffi-scalar` stays Unix-only (it calls `getpid`/libm directly).

`DyLibWin()` in `lib-host.fun` picks the helper's name per host, and the runner
probes for both the DLL and a working `getapi`, adding those cases to its skip
list when either is missing.

The Windows job also runs `build-win64-deps.sh` (x86-64 `libtcc.dll` and
`zlib.dll`), probes both with a real compile/deflate call, builds
`funcmd-safe.exe` with the same feature set, and runs the focused safe test.
The stage step copies only what those probes accepted.

`windows-arm64` is **not a release target yet**. FPC 3.2.2 has no
win64/aarch64 target, and FPC 3.3.1 (trunk), which does, currently produces
binaries that crash with `0xC0000005` on real ARM64 Windows -- including its
own compiler. A bare `writeln('hello')` compiled with `-O-`, `-O1` and `-O2`
reproduces it, so the fault is in FPC's aarch64-win64 backend/RTL (upstream
#42048, #42091), not in Fun. `.github/workflows/winarm64.yml` is a manual
bring-up harness that cross-builds on Linux (through Zig's clang) and runs the
portable suite on `windows-11-arm`; it publishes nothing, and nightly releases
never include a win-arm64 asset. `make-win-arm64.sh` is ready for experiments
and can become a real build once FPC fixes the target.
