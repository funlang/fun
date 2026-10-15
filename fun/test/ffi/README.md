# FFI test cases (Linux / macOS / Windows)

These cases exercise `getapi()` on every host that has it: the libffi path
(`-dLinuxFFI`, `-dDarwinFFI`, `-dWinFFI`, see `art/notes/port-decisions.md`)
plus the local C helper. They started as the Linux FFI scratch cases of commit
`cb40bcd` / `b782a87` (`art/notes/linux-x86_64-port.md` §6) and are now part of
the tracked regression suite: four of the five are listed in
`fun/test/regression-list.txt` and run wherever getapi works, diffed against the
shared snapshots in `fun/test/expected/`.

## Setup

Build the helper C library once, per host:

```sh
fun/test/ffi/build.sh                     # .so / .dylib / .dll, whichever host
```

or by hand:

```sh
cd fun/test/ffi
gcc -O2 -fPIC -shared -o libffitest.so libffitest.c                      # Linux
gcc -O2 -fPIC -dynamiclib -o libffitest.dylib libffitest.c               # macOS
gcc -O2 -shared -Wl,--export-all-symbols -o libffitest.dll libffitest.c  # Windows/MinGW
```

The Windows build needs `-Wl,--export-all-symbols`: libffitest.c has no
`__declspec(dllexport)` and MinGW exports nothing by default, so
`GetProcAddress` would find none of the names the cases call.

## Run

All `.fun` cases assume you run from the repo root (they load the helper via
`DyLibWin()` from `fun/lib/lib-host.fun`: `./fun/test/ffi/libffitest.so` on
Linux, `.dylib` on macOS, `.dll` on Windows):

```sh
src/prj/fun/funcmd fun/test/ffi/ffi-scalar.fun     # libc/libm + scalar int/double
src/prj/fun/funcmd fun/test/ffi/ffi-float.fun      # float args/returns, mixed GPR/XMM
src/prj/fun/funcmd fun/test/ffi/ffi-int64.fun      # 64-bit int args/returns + cb roundtrip
src/prj/fun/funcmd fun/test/ffi/ffi-callbacks.fun  # int/double/int2/string callbacks
src/prj/fun/funcmd fun/test/ffi/ffi-float-cb.fun   # float cb, void cb, nested cb, two cbs
```

## Coverage matrix

| file | covers | hosts |
|------|--------|-------|
| `ffi-scalar.fun` | libc getpid/strlen/atoi/getenv, libm pow/sin (double SSE), helper summ/addi | Linux, macOS (`getpid`/libm are POSIX) |
| `ffi-float.fun` | fsum/fdbl (float `ff:f`), dfromf (`f:d`), mixsum (`idi:d`), five/ident (double return/id) | all three |
| `ffi-int64.fun` | big64/passll/addll (`l`), int64 callback roundtrip | all three |
| `ffi-callbacks.fun` | `@toCallback` int/double/ii/string cb, cb->string return, repeated calls, zero-arg (`c:i`/`c:v`) cbs | all three |
| `ffi-float-cb.fun` | float cb (`fc:f`), acc double repeat, void cb side-effect, two cbs, nested cb | all three |

## Notes / known limits

- The four host-independent cases print nothing but Fun-formatted values, which
  is why they share one snapshot across hosts; the Windows runner compares them
  against the same files and runs them only when both `getapi` and
  `libffitest.dll` are present.
- On Windows, `'kernel32'.getapi('GetCommandLine', ':s')` works even though
  kernel32 actually exports `GetCommandLineA`: `lffi.pas` retries with the `A`
  suffix, the same fallback `io.GetProc` has always applied to the Delphi/win32
  path. Pass an explicit `...W` name to reach the wide entry point.
- Fun's own numeric literals and arithmetic wrap at 32-bit (a language-level
  limit, unrelated to FFI). Feed true 64-bit values in from C (e.g. via
  `big64`) rather than from a Fun literal when testing the `l` type.
- `'w'` (wide-string) args/returns are accepted on Linux FFI but degrade to the
  narrow `'s'` semantics (wchar_t is 4-byte UTF-32, not UTF-16). They no longer
  raise or crash; treat them as plain char* for ASCII-safe calls.
- Struct / array args and C `long double` / complex returns are not covered.
- The `p` pointer parameter type is passed to Fun as a raw numeric address
  (no automatic dereference); use `ptr=true` on `@toCallback` to hand C a raw
  address instead of a managed closure when needed.
