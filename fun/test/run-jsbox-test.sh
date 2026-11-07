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

cd "$ROOT"
exec "$FUNCMD" fun/test/jsbox_test.fun
