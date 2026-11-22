# Packages, tests and packing

This guide covers the project tooling: `package.fun`, `fun package`,
`fun run`, `fun test` and `fun pack`. For building the interpreter, see
[building.md](building.md).

## Contents

- [Packages](#packages)
- [Tests](#tests)
- [Packing](#packing)

---

## Packages

`fun` below is the command-line binary (`fun.exe` on Windows). A project is a
directory with a `package.fun` manifest; `fun package init` creates the
manifest and a minimal template:

```text
fun package init myapp          # package.fun + src/main.fun
fun package init mylib --lib    # package.fun + src/lib.fun
```

```fun
fun package()
  result = [
    name: 'myapp',
    version: '0.1.0',
    bin: 'src/main.fun',
    lib: '',
    'fun': '9.5.7',
    dependencies: [
      'hello': [source: 'github.com/acme/hello', version: 'v1.0.0'],
      'local': [source: '../libs/local']
    ],
    // >>> generated - do not edit; run 'fun package tidy' to refresh
    resolved: []
    // <<< generated
  ];
end fun;
```

- `fun package add <name> <source> [--version <v>]` and `remove <name>` edit
  only the `dependencies` set; versions are exact tags, branches, or commits.
- `fun package tidy` installs the declared revisions into the shared `~/.fun`
  cache (`FUN_HOME` overrides it), verifies git tree hashes, and writes the
  `resolved` block. Path dependencies are used in place; only git
  dependencies need `git`.
- `fun run [args...]` runs the manifest `bin` from the project root. Inside a
  project, `fun <script>` is the flat mode of the same launcher: it runs the
  given script with the project's dependencies available.
- `fun pack` embeds the app and its dependency libraries into one executable;
  the result runs without `~/.fun`.

Runs are read-only: a missing or stale dependency reports
`run 'fun package tidy'` instead of fetching anything. `FUN_PACKAGE_READY=1`
skips project mode (useful for a broken manifest). See
[`fun/demos/package-demo`](../fun/demos/package-demo) for a runnable example,
and [`fun/demos/test-demo`](../fun/demos/test-demo) for a lib-only package with
tests.

A minimal launcher:

```text
myapp/
├── package.fun
├── src/
│   ├── main.fun          # bin: 'src/main.fun'
│   └── lib.fun           # shared library code
└── tests/
    └── lib_test.fun
```

`fun package tidy` is the only step that writes to the cache; `fun run` and
`fun test` never fetch. Version tags may be branches or commits, but pinning a
tag is recommended for reproducible builds.

## Tests

Test files are named `*_test.fun`; their location is free (`tests/` is the
recommended layout). Other `.fun` files are ordinary modules, so tests can
share helpers. A test file imports `test.fun` and registers blocks:

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

`fun test` runs every `*_test.fun` below the project root, one child process
per file, prints `PASS`/`FAIL` per file, and exits non-zero when any test
fails. A project only needs `package.fun` (a `bin` entry is not required);
manifest dependencies are available through the same launcher as `fun run`.

- Assertions: `assert.equal`, `not_equal`, `is_true`, `is_false`, `match`,
  `contains`, `greater`, `less`, `is_nil`, `not_nil`, `raises`, `fail`; each
  takes an optional trailing message.
- `test.skip('reason')` inside a test body ends that test as skipped; the
  reason is optional, skips are counted separately, and they do not fail the
  run. Do not catch it in a broad `try/except`: the test is still reported as
  skipped, but the rest of the body continues.
- `test.todo('name', 'reason')` registers a placeholder that is not run;
  `test.todo('name', { ... }, 'reason')` runs the body and treats a failure as
  expected. A todo body that passes prints `todo passed: ... (remove todo)`.
  Todos are counted separately and do not fail the run.
- `test.fun`, the globals `test`/`assert`/`runTests`, the aliases `as test` /
  `as assert`, and dependency keys `test`/`assert` are reserved. A third-party
  test library can be imported under another alias.
- `dist/`, dot-directories, and path-dependency directories are skipped.

## Packing

`fun pack` produces a single executable from the manifest entry point and its
dependency libraries:

```text
fun pack -o dist/myapp        # uses the manifest bin and default output name
fun pack src/main.fun -o app  # explicit entry and output name
fun pack src/main.fun -a assets -o app  # include an extra file or directory
```

The packed program is self-contained: it does not need `~/.fun`, the source
tree, or the dependency directories. Use it to hand a tool to a machine that
has no package cache. The default output name comes from the manifest.
