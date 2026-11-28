#!/bin/sh
# Build funcmd-ide2, the IDE2 debugger-enabled interpreter.
#
# The default funcmd is intentionally untouched: this mode adds -dIDE2 plus
# the worker runtime (-dFunThreads -dUseCThreads) and writes a separate
# funcmd-ide2 binary in fun/ . Use it for the cross-platform IDE only.
#
# Extra arguments are passed through, e.g.:
#   ./make-linux-x86_64-ide2.sh -dFunTraceback
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
FUN_IDE2=1 exec "$HERE/make-linux-x86_64.sh" "$@"
