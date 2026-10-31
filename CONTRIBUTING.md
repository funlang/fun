# Contributing

Thanks for your interest in contributing to **Fun**! Please follow the conventions below so we can collaborate smoothly.

**English** (this file) · [简体中文](CONTRIBUTING.zh.md)

## Branching & commits

- This project follows a simple single-trunk (`main`) model. Fixes and features are committed directly to `main`.
- Use short, imperative commit messages, e.g.:
  - `Fix: parser handles empty array literal`
  - `Add: lib-yaml round-trip test`
  - `Docs: update build matrix`
- Keep each commit to one logical change so it is easy to bisect.

## Status and roadmap

- `ROADMAP.md` is the **only** source of current status, priorities and accepted
  limitations. `CHANGELOG.md` is the released history.
- If a change fixes or opens an item, flip or add its row in `ROADMAP.md` in the
  same commit.
- Notes under `art/notes/` keep design, evidence and history, not a second status list.
- `sh src/prj/fun/check-roadmap.sh` runs in the `docs` CI workflow.

## Encoding & line endings

- The language core is Pascal (Delphi / Free Pascal); source files use **CRLF** line endings (Windows toolchain).
- Some legacy files are GBK-encoded. **Prefer UTF-8 for new/modified files**, and preserve the encoding and line endings of existing files to avoid noisy whole-file diffs.
- Do not commit build artifacts (`.exe/.dll/.obj/.dcu/.ppu/.res/.dof/.cfg`, etc.) — they are covered by `.gitignore`.

## Directory conventions

| Path          | Contents                                  |
| ------------- | ----------------------------------------- |
| `src/core/`   | Interpreter core (value model, objects, control flow) |
| `src/parse/`  | Lexer/parser (`bnf/fun.ebnf`)             |
| `src/lib/`    | Built-in runtime library                  |
| `fun/lib/`    | Standard library written in Fun           |
| `fun/demo/`   | Language syntax demos                     |
| `fun/demos/`  | Full applications and benchmarks          |

## Standard library guidelines

For modules in `fun/lib`:

- Keep the copyright header and `SPDX-License-Identifier: MIT`.
- Document the built-in functions, parameters, and behavior in the leading `# lib-xxx` comment block.
- Add a matching test script under `fun/demo/` to exercise your changes.

## Building

Build scripts live in `src/prj/fun/` (Delphi 2006/2009 and Free Pascal 2.4.0, with Windows/Linux/ARM/WinCE cross-compilation); on a native x86_64 Linux host use `src/prj/fun/make-linux-x86_64.sh`, and for the macOS / Linux-aarch64 cross builds (also from an x86_64 Linux build machine) see [Building -> Cross builds](README.md#cross-builds-macos-and-linux-aarch64-from-linux-x86_64). After touching the parser, keep the grammar definitions `src/parse/bnf/fun.ebnf`, `yacc.y`, and `lex.l` in sync.

> The repo does **not** carry third-party sources/binaries (PCRE, the Tiny C Compiler, the Windows runtime DLLs). Before building, fetch them and drop them in the documented locations - see [Building -> Third-party dependencies](README.md#third-party-dependencies-not-carried-in-the-repo). A missing one only **degrades** the build; it does not stop it.

## Opening a Pull Request

1. `git pull` to sync with the latest `main`.
2. Create a feature branch, make your change, and add tests.
3. Run the relevant demo scripts to confirm behavior.
4. Open a Pull Request describing the change and how it was verified.

---

Questions or commercial licensing inquiries: &lt;zwd@funlang.org&gt;.
