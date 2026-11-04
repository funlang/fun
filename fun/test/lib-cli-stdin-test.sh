#!/bin/sh
# cli: ctx.stdin() reads process stdin by default.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FUNCMD="$ROOT/fun/funcmd"
[ -x "$FUNCMD" ] || FUNCMD="$ROOT/src/prj/fun/funcmd"
[ -x "$FUNCMD" ] || FUNCMD="$ROOT/fun/fun"
[ -x "$FUNCMD" ] || { echo "funcmd not built"; exit 2; }

TMP="$(mktemp "${TMPDIR:-/tmp}/fun-cli-stdin.XXXXXX")"
trap 'rm -f "$TMP.out" "$TMP.err" "$TMP.exp"' EXIT

printf 'abcdef' | "$FUNCMD" "$ROOT/fun/test/lib-cli-stdin-test.fun" >"$TMP.out" 2>"$TMP.err"
rc=$?
printf 'abcdef' > "$TMP.exp"

echo "stdin_rc=$rc"
if [ "$rc" -eq 0 ] && cmp -s "$TMP.out" "$TMP.exp" && [ ! -s "$TMP.err" ]; then
  echo "stdin=PASS"
else
  echo "stdin=FAIL"
  echo "stdout:"
  sed 's/^/  /' "$TMP.out"
  echo "stderr:"
  sed 's/^/  /' "$TMP.err"
  exit 1
fi
