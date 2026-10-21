# test-demo

A minimal Fun package with tests. `fun test` discovers every `*_test.fun`
under the project root; other `.fun` files are ordinary modules, so tests can
share helpers.

```text
package.fun               # manifest (lib-only: no bin entry)
src/lib.fun               # code under test
tests/calc_test.fun       # tests; imports test.fun
tests/helpers.fun         # shared helper; imports test.fun for assertions
```

`fun` below is the command-line binary (`fun.exe` on Windows). From the
repository root, after building, the in-tree binary is `src/prj/fun/funcmd`;
from this directory that is `../../../src/prj/fun/funcmd`.

```text
cd fun/demos/test-demo

fun test
# tests/calc_test.fun   PASS (4)
# 1 file, 4 tests: all passed
```

A failing assertion prints the test name and a diagnostic; the exit code is 1:

```fun
test('broken', {
  assert.equal(add(1, 1), 3, 'math is broken');
});
```

```text
fun test
# tests/calc_test.fun   FAIL
# not ok broken
#   math is broken
#   expected 3, got 2
# 1 file, 5 tests: 4 passed, 1 failed
```

Notes:

- Only names ending `_test.fun` are tests; their location is free (`tests/` is
  the recommended layout). `dist/`, dot-directories, and path-dependency
  directories are skipped.
- A project only needs `package.fun`; a `bin` entry is not required. Manifest
  dependencies are available through the same project launcher as `fun run`.
- `test.fun`, the globals `test`/`assert`/`runTests`, the aliases `as test` /
  `as assert`, and dependency keys `test`/`assert` are reserved. Import a
  third-party test library under another alias.
- A helper that uses assertions `use 'test.fun';` itself; a plain helper does
  not need it.
