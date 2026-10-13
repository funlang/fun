#!/bin/sh
# ============================================================
# Fun - Linux regression runner (core demos + portable lib tests + FFI smoke)
#
# Usage:
#   ./run-linux-regression.sh              # verify against snapshots
#   ./run-linux-regression.sh --update     # (re)generate snapshots
#   ./run-linux-regression.sh --list       # show the must-pass list
#
# Run from the repository root:
#   fun/test/run-linux-regression.sh
#
# The test list lives in fun/test/regression-list.txt (name<TAB>script<TAB>mode)
# and is shared with fun/test/run-windows-regression.bat.
#
# Two kinds of checks:
#   snap  - output must match fun/test/expected/<name>.txt byte for byte
#           (a mismatch prints the first 20 diff lines, so a failure on another
#            host/word size can be read directly instead of hunted for)
#   smoke - only exit code 0 and no crash markers (for nondeterministic output)
#
# Windows-only tests (lib-winapi-test, lib-winole-test) are deliberately NOT in
# the list: user32.dll/COM do not exist on Linux and they can never pass here.
#
# Which entries are HOST-DEPENDENT, i.e. their snapshots only hold for a Linux
# 64-bit host (they assert '/' paths, "address > 4GB", the 'host'.arg() facts, or
# the list of modules that need Windows libraries):
#   builtin-dispatch (prints 'host'.arg), lib-host-test, lib-param-linux,
#   lib-cmdline-linux, lib-loadcheck, libc-outbuf, ptr-primitives,
#   raw-address-getapi (needs the Linux .so helper), lib-tcc-test / lib-jit-test
#   (need libtcc.so next to funcmd, built by make-linux-x86_64.sh from src/3rd/tcc),
#   lib-asm-lnx (mmap'd executable memory + 64-bit callback addresses),
#   fractal-asm-x64 (same, and it prints a wall-clock timing line, so it runs as
#                   a smoke check instead of a snapshot),
#   lib-asm-a64 (encoder snapshot is portable, but its final "exec" line names
#                the host cpu),
#   lib-hash-test (str.md5/sha1 need the -dMD5 define)
# run-benchmarks is host-dependent for a different reason: it needs a POSIX shell
# and a symlinked lib/ layout.
# The rest - the demo suite, the FFI suite, lib-func-check, lib-bnf-dedup,
# lib-regex-replace, portability-probe, lib-orm-rows - have host-independent output and are the
# ones worth running on
# Windows/32-bit (regenerate the snapshots there with --update, then diff).
# ============================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FUNCMD="$ROOT/src/prj/fun/funcmd"
EXPECTED="$HERE/expected"

cd "$ROOT" || exit 2

if [ ! -x "$FUNCMD" ]; then
    echo "funcmd not found at $FUNCMD" >&2
    echo "Build it first: cd src/prj/fun && ./make-linux-x86_64.sh" >&2
    exit 2
fi

# name<TAB>script<TAB>mode

# Test list is shared with run-windows-regression.bat (name<TAB>script<TAB>mode).
LISTFILE="$HERE/regression-list.txt"
if [ ! -f "$LISTFILE" ]; then
    echo "missing $LISTFILE" >&2
    exit 2
fi

update=0
case "${1:-}" in
    --list)
        awk -F'\t' '{printf "%-24s %-30s %s\n", $1, "fun/"$2, $3}' "$LISTFILE"
        exit 0
        ;;
    --update)
        update=1
        mkdir -p "$EXPECTED"
        ;;
    "") ;;
    *)
        echo "usage: $0 [--update|--list]" >&2
        exit 2
        ;;
esac

fail=0
total=0
failures=''

printf '%-26s %s\n' "TEST" "RESULT"
printf '%-26s %s\n' "--------------------------" "------"

while IFS="$(printf '\t')" read -r name script testmode; do
    [ -z "$name" ] && continue
    total=$((total + 1))
    detail=''
    if [ "$testmode" = "shell" ]; then
        out="$(sh "fun/$script" 2>&1 | tr -d '\r')"
    else
        out="$("$FUNCMD" "fun/$script" 2>&1)"
    fi
    rc=$?
    result=""

    if [ "$testmode" = "smoke" ]; then
        if [ "$rc" -ne 0 ]; then
            result="FAIL(rc=$rc)"
        elif printf '%s' "$out" | grep -qiE "access violation|syntax error|stack overflow|runtime error"; then
            result="FAIL(crash marker)"
        else
            result="PASS"
        fi
    elif [ "$update" = "1" ]; then
        printf '%s' "$out" > "$EXPECTED/$name.txt"
        result="SNAPSHOT"
    elif [ "$rc" -ne 0 ]; then
        result="FAIL(rc=$rc)"
    elif [ ! -f "$EXPECTED/$name.txt" ]; then
        result="FAIL(no snapshot; run --update)"
    elif ! printf '%s' "$out" | diff -q - "$EXPECTED/$name.txt" >/dev/null 2>&1; then
        result="FAIL(output differs)"
        detail=$(printf '%s' "$out" | diff -u "$EXPECTED/$name.txt" - | head -20)
    else
        result="PASS"
    fi

    case "$result" in
        FAIL*) fail=$((fail + 1)); failures="$failures $name" ;;
    esac
    printf '%-26s %s\n' "$name" "$result"
    [ -n "$detail" ] && printf '%s\n' "$detail" | sed 's/^/    | /'
done < "$LISTFILE"

echo
echo "$((total - fail))/$total checks passed"
if [ "$fail" -ne 0 ]; then
    echo "failed:$failures"
    exit 1
fi
exit 0
