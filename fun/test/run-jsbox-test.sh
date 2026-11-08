#!/bin/sh
# ============================================================
# Fun - build fun-jsbox and run the end-to-end sandbox tests.
#
#   fun/test/run-jsbox-test.sh
#   FUNCMD=/path/to/funcmd fun/test/run-jsbox-test.sh
#   CC=clang fun/test/run-jsbox-test.sh
#
# The worker source is QuickJS-ng, fetched on demand by
# src/prj/fun/build-jsbox.sh. The test script itself is
# fun/test/jsbox_test.fun and can also be run directly:
#
#   fun/funcmd fun/test/jsbox_test.fun
# ============================================================
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FUNCMD="${FUNCMD:-$ROOT/fun/funcmd}"

if [ ! -x "$FUNCMD" ]; then
    echo "run-jsbox-test: interpreter not found: $FUNCMD" >&2
    echo "  build it first with src/prj/fun/make-linux-x86_64.sh" >&2
    exit 1
fi

"$ROOT/src/prj/fun/build-jsbox.sh"

# On Linux the worker must install its seccomp allowlist by default, and a
# forbidden syscall must kill it. --selftest-seccomp performs openat after the
# filter is active; 159 is 128+SIGSYS.
if [ "$(uname -s 2>/dev/null)" = "Linux" ]; then
    set +e
    "$ROOT/fun/fun-jsbox" --selftest-seccomp >/dev/null 2>&1
    SECCOMP_RC=$?
    set -e
    if [ "$SECCOMP_RC" -ne 159 ]; then
        echo "run-jsbox-test: seccomp self-test failed (exit $SECCOMP_RC, expected 159)" >&2
        exit 1
    fi
    FUN_JSBOX_EXPECT_SECCOMP=1
    export FUN_JSBOX_EXPECT_SECCOMP
fi

# Oversized stdin must be rejected without draining an infinite stream forever.
if [ -r /dev/zero ] && command -v timeout >/dev/null 2>&1; then
    if ! timeout 5 "$ROOT/fun/fun-jsbox" < /dev/zero | grep -q '"kind":"input_limit"'; then
        echo "run-jsbox-test: infinite stdin did not return input_limit" >&2
        exit 1
    fi
fi

cd "$ROOT"
exec "$FUNCMD" fun/test/jsbox_test.fun
