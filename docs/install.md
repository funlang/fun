# Installing Fun

Prebuilt interpreters are attached to
[GitHub Releases](https://github.com/funlang/fun/releases). For builds from
source, see [building.md](building.md).

## Contents

- [Release archives](#release-archives)
- [macOS and Linux](#macos-and-linux)
- [Windows](#windows)
- [What is in an archive](#what-is-in-an-archive)
- [Runtime requirements](#runtime-requirements)

---

## Release archives

- Linux x64 / arm64: `.tar.gz`, with `libtcc.so`, `fun-mt` and the standard
  `lib/`;
- Linux LoongArch64: `.tar.gz`, published in **nightly prereleases only**
  while FPC's loongarch64 backend is still on mainline. The full build has
  regex, `getapi`/FFI and the native asm backend (`lib-asm-loongarch64`), but
  no `libtcc` (runtime C). It also ships `fun-mt`. Stable releases do not
  include it;
- Linux riscv64: `.tar.gz`, published in **nightly prereleases only** while
  FPC's riscv64 backend is still on mainline. The full build has regex,
  `getapi`/FFI, the `-lnx` backends and `lib-asm-riscv64`, but no `libtcc`
  (runtime C). It also ships `fun-mt`. Stable releases do not include it;
- macOS x64 / arm64: `.zip`. Both archives include `libtcc.dylib` and `fun-mt`.
  These builds are **unsigned and not notarized**; use the bundled
  `install.sh --local` (curl does not set the quarantine attribute) or run
  `xattr -dr com.apple.quarantine <dir>` after extracting;
- Windows x64: `.7z`. The build is unsigned, so SmartScreen may warn; extract
  with 7-Zip and double-click `install.cmd` (or run
  `powershell -ExecutionPolicy Bypass -File install.ps1`). The archive ships
  `fun.exe`, `fun-safe.exe`, `fun-mt.exe`, the installers, and the x86-64
  runtime DLLs (`pcre3.dll`, `ffi.dll`, `libtcc.dll`, `zlib.dll`) that the CI
  built; `capabilities.json` records anything a particular build could not
  provide.

## macOS and Linux

One-liner (verifies `SHA256SUMS`, installs under `~/.fun`):

```bash
curl -fsSL https://raw.githubusercontent.com/funlang/fun/main/install.sh | sh
```

If the latest stable release has no binaries yet, the installer says so and
falls back to the newest nightly. Pass `--tag` or `--nightly` to choose
explicitly. The default install links `fun` into `~/.local/bin`; when that
directory is not on `PATH`, add `--add-path` to append a marker-delimited
block to `~/.profile` (or `~/.zshrc` for zsh), or pass `--bin-dir DIR` to put
the links somewhere already on `PATH`.

To install an extracted archive offline, run `./install.sh --local` from its
root. `install.sh` is included in every Unix archive (not only macOS) and also
creates `funcmd` and `funcmd-safe` compatibility symlinks.

## Windows

Windows install (per-user, no administrator rights):

1. Extract the `.7z` archive with 7-Zip.
2. Double-click `install.cmd` in the extracted folder.

`install.cmd` copies the tree to `%LOCALAPPDATA%\Programs\Fun`, adds
`%LOCALAPPDATA%\Programs\Fun\fun` to the user `PATH`, registers `.fun`,
`.foo` and `.fxx` with a `Fun Script` ProgID (so double-clicking a script
runs it), adds a Win+R `fun` entry, and appears in **Settings > Apps** for
uninstalling.

Useful options:

- `-AllUsers` (elevated, under `Program Files`)
- `-Dir DIR`
- `-NoPath`
- `-NoAssoc`
- `-Portable`

Run `uninstall.cmd` from the install directory, or use **Settings > Apps**, to
remove it. Windows may keep an existing per-user choice for an extension; use
**Open with > Choose another app** once to select Fun.

## What is in an archive

Each archive contains a `fun/` runtime tree: `fun/fun` (`fun/fun.exe` on
Windows), `fun/fun-safe` (the capability-restricted build), and `fun/fun-mt`
where the worker build is available, plus `lib/`, `demo/`, `demos/` and the
regression suite in `test/`.

Run `./fun/fun --help`, or run the shipped suite with
`./fun/test/run-linux-regression.sh` on Linux/macOS and
`fun\test\run-windows-regression.bat --portable` on Windows.

Both installers are packaged next to the runtime tree and are the supported way
to get a global `fun` command.

## Runtime requirements

- Linux artifacts are built on Ubuntu 24.04, so they need glibc 2.34 or newer.
- When `getapi`/FFI is enabled, Linux also needs `libffi.so.8` at run time.
- Nightly builds are prereleases, so `releases/latest` stays on the stable
  version.
- `fun.dll` is a separate licensed product and is not part of these archives.

Every release also carries `capabilities.json` and `SHA256SUMS`; optional
features that were unavailable are listed there.
