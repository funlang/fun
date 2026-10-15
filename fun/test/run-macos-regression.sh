#!/bin/sh
# macOS entry point for the regression suite.
#
# The runner in run-linux-regression.sh auto-detects the host, so this is a
# thin, clearly-named wrapper: it forces the macOS platform id (macos, or
# macos-aarch64 on Apple Silicon, so the macOS skip list and the expected/macos*/
# snapshots are used even if `uname` is odd) and forwards the arguments. On a
# genuine macOS host you can also call the runner directly.
#
# Usage, from the repository root:
#   fun/test/run-macos-regression.sh              # verify
#   fun/test/run-macos-regression.sh --update     # write the host's expected/<platform>/*.txt
#   fun/test/run-macos-regression.sh --list
#
# Build first (native FPC):  cd src/prj/fun && ./make-macos.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# Apple Silicon has its own snapshot dir (expected/macos-aarch64/); it still
# reads the macos skip list (see the runner's platform fallback).
case "$(uname -m 2>/dev/null)" in
    arm64|aarch64) FUNREG_PLATFORM=macos-aarch64 ;;
    *)             FUNREG_PLATFORM=macos ;;
esac
export FUNREG_PLATFORM
exec sh "$HERE/run-linux-regression.sh" "$@"
