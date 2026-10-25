#!/bin/sh
# ============================================================
# Fun - safe-build capability regression
#
# Runs the focused capability test against the compile-time safe binary
# (funcmd-safe). The default build and its full regression suite are
# deliberately untouched.
#
# Usage (from the repository root):
#   fun/test/run-safe-regression.sh [strict|readonly]
#   FUNCMD=/path/to/funcmd-safe fun/test/run-safe-regression.sh
# ============================================================
set -u

MODE="${1:-strict}"
case "$MODE" in
    strict)   TESTNAME=safe-mode-test.fun ;;
    readonly) TESTNAME=safe-readonly-test.fun ;;
    *) echo "usage: $0 [strict|readonly]" >&2; exit 2 ;;
esac

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FUNCMD="${FUNCMD:-$ROOT/src/prj/fun/funcmd-safe}"
TEST="$HERE/$TESTNAME"

if [ ! -x "$FUNCMD" ]; then
    # The build script also copies it next to the runtime libs.
    if [ -x "$ROOT/fun/funcmd-safe" ]; then
        FUNCMD="$ROOT/fun/funcmd-safe"
    else
        echo "funcmd-safe not found at $FUNCMD" >&2
        echo "Build it first: cd src/prj/fun && SAFE=1 ./make-linux-x86_64.sh" >&2
        exit 2
    fi
fi

cd "$ROOT" || exit 2

echo "safe mode: $MODE"
echo "safe binary: $FUNCMD"
OUT="$("$FUNCMD" "$TEST" 2>&1)"
RC=$?
printf '%s\n' "$OUT"

if [ "$RC" -ne 0 ]; then
    echo "safe regression: interpreter exited $RC" >&2
    exit 1
fi

SUMMARY="$(printf '%s\n' "$OUT" | tail -n 1)"
case "$SUMMARY" in
    *"failed: 0"*) ;;
    *)
        echo "safe regression: no clean summary (got: $SUMMARY)" >&2
        exit 1
        ;;
esac

# Make sure the test file actually registered tests, so an accidental empty
# run cannot pass.
TOTAL="$(printf '%s\n' "$SUMMARY" | sed -n 's/.*# tests: \([0-9][0-9]*\).*/\1/p')"
if [ -z "$TOTAL" ] || [ "$TOTAL" -lt 5 ]; then
    echo "safe regression: expected at least 5 tests, got '${TOTAL:-none}'" >&2
    exit 1
fi

echo "safe regression: $TOTAL/$TOTAL passed"
