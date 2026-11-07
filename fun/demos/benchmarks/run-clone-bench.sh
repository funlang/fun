#!/bin/sh
# Run the clone/new benchmark several times and report min/median wall time.
#
#   fun/demos/benchmarks/run-clone-bench.sh
#   FUNCMD=/tmp/funcmd-baseline fun/demos/benchmarks/run-clone-bench.sh
#   RUNS=7 FUNCMD=./fun/funcmd fun/demos/benchmarks/run-clone-bench.sh
#
# The script prints each run, the minimum, the median, and the checksum. Use
# the same RUNS and machine when comparing two interpreters.

set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
FUNCMD="${FUNCMD:-$ROOT/fun/funcmd}"
RUNS="${RUNS:-5}"
SCRIPT="$HERE/clone-bench.fun"

[ -x "$FUNCMD" ] || { echo "run-clone-bench: not executable: $FUNCMD" >&2; exit 1; }

cd "$ROOT"

tmp="$(mktemp "${TMPDIR:-/tmp}/fun-clone-bench-XXXXXX")"
trap 'rm -f "$tmp"' EXIT INT TERM

checksum=""
i=1
while [ "$i" -le "$RUNS" ]; do
    line="$("$FUNCMD" "$SCRIPT")"
    ms="$(printf '%s\n' "$line" | sed -n 's/.* ms=\([0-9.]*\).*/\1/p')"
    sum="$(printf '%s\n' "$line" | sed -n 's/.* checksum=\([-0-9]*\).*/\1/p')"
    [ -n "$ms" ] || { echo "run-clone-bench: unexpected output: $line" >&2; exit 1; }
    if [ -z "$checksum" ]; then
        checksum="$sum"
    elif [ "$checksum" != "$sum" ]; then
        echo "run-clone-bench: checksum changed: $checksum -> $sum" >&2
        exit 1
    fi
    printf 'run %s: %s ms\n' "$i" "$ms"
    printf '%s\n' "$ms" >> "$tmp"
    i=$((i + 1))
done

sort -n "$tmp" | awk -v n="$RUNS" '
    { a[NR] = $1 }
    END {
        if (NR == 0) exit 1;
        min = a[1];
        if (NR % 2 == 1) med = a[(NR + 1) / 2];
        else med = (a[NR / 2] + a[NR / 2 + 1]) / 2;
        printf "min=%.3f ms  median=%.3f ms  runs=%d  checksum=%s\n", min, med, n, "'"$checksum"'";
    }
'
