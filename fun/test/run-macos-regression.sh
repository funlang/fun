#!/bin/sh
# macOS entry point for the regression suite.
#
# The runner in run-linux-regression.sh auto-detects the host, so this is a
# thin, clearly-named wrapper: it forces PLATFORM=macos (so the macOS skip list
# and fun/test/expected/macos/ snapshots are used even if `uname` is odd) and
# forwards the arguments. On a genuine macOS host you can also call the runner
# directly.
#
# Usage, from the repository root:
#   fun/test/run-macos-regression.sh              # verify
#   fun/test/run-macos-regression.sh --update     # write expected/macos/*.txt
#   fun/test/run-macos-regression.sh --list
#
# Build first (native FPC):  cd src/prj/fun && ./make-macos.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
FUNREG_PLATFORM=macos
export FUNREG_PLATFORM
exec sh "$HERE/run-linux-regression.sh" "$@"
