#!/bin/sh
# Run the worker/shared-store tests with the MT build.
#
# Build the binary first:
#   src/prj/fun/make-linux-x86_64-mt.sh
#
# Override the binary with FUNCMD=/path/to/funcmd-mt when needed.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
FUNCMD="${FUNCMD:-fun/funcmd-mt}"
if [ ! -x "$FUNCMD" ]; then
    echo "missing $FUNCMD; run src/prj/fun/make-linux-x86_64-mt.sh first" >&2
    exit 2
fi
exec "$FUNCMD" fun/test/lib-worker-test.fun
