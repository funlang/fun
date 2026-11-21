#!/bin/sh
# Build funcmd-mt, the worker-capable Fun interpreter.
#
# This is the default funcmd plus -dFunThreads -dUseCThreads. It is a separate
# binary on purpose: cthreads makes every allocation lock, which costs about
# 12-15% on single-threaded scripts. Use funcmd for normal scripts and
# funcmd-mt for scripts that use lib-worker.
#
# Extra arguments are passed through, e.g.:
#   ./make-linux-x86_64-mt.sh -dFunTraceback
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
FUN_THREADS=1 exec "$HERE/make-linux-x86_64.sh" "$@"
