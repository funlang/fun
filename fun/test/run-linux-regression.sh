#!/bin/sh
# ============================================================
# Fun - POSIX regression runner (core demos + portable lib tests + FFI smoke)
#
# Runs on Linux and macOS; the host is auto-detected (see HOST PLATFORMS below).
# The Windows counterpart is run-windows-regression.bat.
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
#   snap  - output must match a snapshot byte for byte (a mismatch prints the
#           first 20 diff lines, so a failure on another host/word size can be
#           read directly instead of hunted for)
#   smoke - only exit code 0 and no crash markers (for nondeterministic output)
#
# HOST PLATFORMS
# --------------
# PLATFORM is derived from `uname -s` (linux / macos) and can be overridden with
# FUNREG_PLATFORM=<name>. Two per-platform files tune the run:
#
#   fun/test/regression-skip-<platform>.txt   name<TAB>reason for tests that
#       cannot run on that host at all (a Linux-only /proc or libc.so backend,
#       an unimplemented JIT, ...). Skipped tests are reported as SKIP and do
#       not count as failures.
#   fun/test/expected/<platform>/<name>.txt   a host-specific snapshot that
#       overrides the shared fun/test/expected/<name>.txt for that host. Only
#       tests whose *portable* output legitimately differs per host need one;
#       writing a snapshot with --update on a host fills its directory.
#
# FUNCMD=... overrides the interpreter path (default src/prj/fun/funcmd).
#
# Which entries are HOST-DEPENDENT on this (Linux 64-bit) host, i.e. their
# shared snapshots only hold there (they assert '/' paths, "address > 4GB", the
# 'host'.arg() facts, or the list of modules that need unavailable libraries):
#   builtin-dispatch, lib-host-test, lib-param-linux, lib-cmdline-linux,
#   lib-loadcheck, libc-outbuf, ptr-primitives,
#   raw-address-getapi (needs the Linux .so helper), lib-tcc-test / lib-jit-test
#   (need libtcc.so next to funcmd, built by make-linux-x86_64.sh from src/3rd/tcc),
#   lib-asm-lnx (mmap'd executable memory + 64-bit callback addresses),
#   fractal-asm-x64 (same, and it prints a wall-clock timing line, so it runs as
#                   a smoke check instead of a snapshot),
#   lib-asm-a64 (encoder snapshot is portable, but its final "exec" line names
#                the host cpu, and it needs executable memory),
#   lib-hash-test (str.md5/sha1 need the -dMD5 define)
# run-benchmarks needs a POSIX shell and a symlinked lib/ layout.
# The rest - the demo suite, the FFI suite, lib-func-check, lib-bnf-dedup,
# lib-regex-replace, portability-probe, lib-orm-rows - have host-independent
# output and are the ones worth running on Windows/32-bit (regenerate the
# snapshots there with --update, then diff).
#
# See art/notes/macos-port.md for the macOS state and the per-test skip reasons
# in fun/test/regression-skip-macos.txt.
# ============================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FUNCMD="${FUNCMD:-$ROOT/src/prj/fun/funcmd}"
EXPECTED="$HERE/expected"

# --- host platform ---------------------------------------------------------
HOSTOS="$(uname -s 2>/dev/null | tr 'A-Z' 'a-z')"
case "$HOSTOS" in
    darwin) PLATFORM=macos ;;
    linux)  PLATFORM=linux ;;
    *)      PLATFORM="$HOSTOS" ;;
esac
PLATFORM="${FUNREG_PLATFORM:-$PLATFORM}"
PLATFORM_EXPECTED="$EXPECTED/$PLATFORM"
SKIPFILE="$HERE/regression-skip-$PLATFORM.txt"

# --update writes into the host's own snapshot dir on non-Linux hosts, so the
# shared Linux snapshots stay the common baseline; Linux keeps writing to
# expected/ directly (unchanged).
if [ "$PLATFORM" = "linux" ]; then SNAPDIR="$EXPECTED"; else SNAPDIR="$PLATFORM_EXPECTED"; fi

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

# Is NAME in the platform skip file? Prints its reason and returns 0 if so.
skip_reason() {
    [ -f "$SKIPFILE" ] || return 1
    awk -F'\t' -v n="$1" '$1==n { print ($2=="" ? "platform-specific" : $2); found=1; exit } END { exit(found?0:1) }' "$SKIPFILE"
}

# The snapshot a test is compared against: the host-specific one if it exists,
# else the shared baseline. Prints the path (may not exist).
snapshot_for() {
    if [ -f "$PLATFORM_EXPECTED/$1.txt" ]; then
        printf '%s/%s.txt\n' "$PLATFORM_EXPECTED" "$1"
    else
        printf '%s/%s.txt\n' "$EXPECTED" "$1"
    fi
}

update=0
case "${1:-}" in
    --list)
        awk -F'\t' -v plat="$PLATFORM" '{printf "%-24s %-30s %-5s %s\n", $1, "fun/"$2, $3, plat}' "$LISTFILE"
        if [ -f "$SKIPFILE" ]; then
            echo
            echo "skipped on $PLATFORM:"
            awk -F'\t' '!/^#/ && NF{printf "  %-24s %s\n", $1, $2}' "$SKIPFILE"
        fi
        exit 0
        ;;
    --update)
        update=1
        mkdir -p "$SNAPDIR"
        ;;
    "") ;;
    *)
        echo "usage: $0 [--update|--list]" >&2
        exit 2
        ;;
esac

fail=0
total=0
skipped=0
failures=''

printf 'platform: %s%s\n' "$PLATFORM" "$( [ -f "$SKIPFILE" ] && printf ' (skip list: %s)' "${SKIPFILE##*/}" )"
printf '%-26s %s\n' "TEST" "RESULT"
printf '%-26s %s\n' "--------------------------" "------"

while IFS="$(printf '\t')" read -r name script testmode; do
    [ -z "$name" ] && continue

    reason="$(skip_reason "$name" 2>/dev/null)" && {
        printf '%-26s %s\n' "$name" "SKIP ($reason)"
        skipped=$((skipped + 1))
        continue
    }

    total=$((total + 1))
    detail=''
    if [ "$testmode" = "shell" ]; then
        out="$(sh "fun/$script" 2>&1 | tr -d '\r')"
    else
        out="$("$FUNCMD" "fun/$script" 2>&1)"
    fi
    rc=$?
    result=""
    snap="$(snapshot_for "$name")"

    if [ "$testmode" = "smoke" ]; then
        if [ "$rc" -ne 0 ]; then
            result="FAIL(rc=$rc)"
        elif printf '%s' "$out" | grep -qiE "access violation|syntax error|stack overflow|runtime error"; then
            result="FAIL(crash marker)"
        else
            result="PASS"
        fi
    elif [ "$update" = "1" ]; then
        printf '%s' "$out" > "$SNAPDIR/$name.txt"
        result="SNAPSHOT"
    elif [ "$rc" -ne 0 ]; then
        result="FAIL(rc=$rc)"
    elif [ ! -f "$snap" ]; then
        result="FAIL(no snapshot; run --update)"
    elif ! printf '%s' "$out" | diff -q - "$snap" >/dev/null 2>&1; then
        result="FAIL(output differs)"
        detail=$(printf '%s' "$out" | diff -u "$snap" - | head -20)
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
echo "$((total - fail))/$total checks passed$( [ "$skipped" -gt 0 ] && printf ' (%s skipped)' "$skipped" )"
if [ "$fail" -ne 0 ]; then
    echo "failed:$failures"
    exit 1
fi
exit 0
