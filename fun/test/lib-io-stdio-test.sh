#!/bin/sh
# Process stdin/stdout/stderr through io.stdin/stdout/stderr.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FUNCMD="$ROOT/fun/funcmd"
[ -x "$FUNCMD" ] || FUNCMD="$ROOT/src/prj/fun/funcmd"
[ -x "$FUNCMD" ] || { echo "funcmd not built"; exit 2; }

TMP="$(mktemp "${TMPDIR:-/tmp}/fun-io-stdio.XXXXXX")"
trap 'rm -f "$TMP.out" "$TMP.err" "$TMP.eout" "$TMP.eerr" "$TMP.in" "$TMP.bin" "$TMP.copyerr" "$TMP.all" "$TMP.allerr"' EXIT

printf 'abcdef' | "$FUNCMD" "$ROOT/fun/test/lib-io-stdio-test.fun" >"$TMP.out" 2>"$TMP.err"
rc=$?

echo "rc=$rc"
echo "stdout:"
sed 's/^/  /' "$TMP.out"
echo "stderr:"
sed 's/^/  /' "$TMP.err"

printf '' | "$FUNCMD" "$ROOT/fun/test/lib-io-stdio-test.fun" >"$TMP.eout" 2>"$TMP.eerr"
erc=$?
echo "eof_rc=$erc"
echo "eof_stdout:"
sed 's/^/  /' "$TMP.eout"
echo "eof_stderr:"
sed 's/^/  /' "$TMP.eerr"

printf '\000\001\012\377AB' > "$TMP.in"
"$FUNCMD" "$ROOT/fun/test/lib-io-stdio-copy.fun" < "$TMP.in" > "$TMP.bin" 2>"$TMP.copyerr"
crc=$?
echo "copy_rc=$crc"
if cmp -s "$TMP.in" "$TMP.bin"; then echo "binary=PASS"; else echo "binary=FAIL"; fi
if [ -s "$TMP.copyerr" ]; then echo "copy_stderr:"; sed 's/^/  /' "$TMP.copyerr"; fi

"$FUNCMD" "$ROOT/fun/test/lib-io-stdio-readall.fun" < "$TMP.in" > "$TMP.all" 2>"$TMP.allerr"
arc=$?
echo "readall_rc=$arc"
if cmp -s "$TMP.in" "$TMP.all"; then echo "readall=PASS"; else echo "readall=FAIL"; fi
if [ -s "$TMP.allerr" ]; then echo "readall_stderr:"; sed 's/^/  /' "$TMP.allerr"; fi
