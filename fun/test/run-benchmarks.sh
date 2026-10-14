#!/bin/sh
# Real-workload smoke: run the shipped benchmarks on this host.
#
# These scripts `use 'lib-time.fun'` etc. with bare names, and Fun resolves bare
# `use` names relative to the *script's* directory - i.e. they assume the shipped
# layout (executable + lib/ side by side), not the source tree. So they are run
# from a scratch dir where lib/ sits next to the script.
#
# Only deterministic output is printed: fractal-benchmark.fun prints its ASCII
# fractal (deterministic) followed by `: <duration ms>` (not deterministic), so
# the timing lines are filtered out; test-high-level-language.fun is fully
# deterministic.
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 2
FUNCMD="$ROOT/src/prj/fun/funcmd"
# GNU `timeout` is not part of a stock macOS userland; use it when present so a
# hung benchmark cannot wedge CI, and fall back to a plain run otherwise.
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT="timeout 600"
else
    TIMEOUT=""
fi
B="fun/test/.bench"

rm -rf "$B"
mkdir -p "$B"
ln -sfn "$ROOT/fun/lib" "$B/lib"
cp "$FUNCMD" "$B/funcmd"
cp fun/demos/benchmarks/fractal-benchmark.fun \
   fun/demos/benchmarks/test-high-level-language.fun "$B/"

echo "--- fractal-benchmark: deterministic output (timings filtered) ---"
( cd "$B" && $TIMEOUT ./funcmd fractal-benchmark.fun 2>&1 | tr -d '\r' | grep -v '^: ' )
echo "--- fractal done ---"

echo "--- test-high-level-language ---"
( cd "$B" && $TIMEOUT ./funcmd test-high-level-language.fun 2>&1 | tr -d '\r' )

# test-speed.fun (a 100M-iteration loop, prints only timings) is deliberately
# not part of the default run: it costs ~11s and adds no deterministic output.
# Run it by hand when you want the stress:  ./funcmd test-speed.fun

rm -rf "$B"
