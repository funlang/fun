#!/bin/sh
# ============================================================
# Fun - verify the runtime floor of a Linux build.
#
# Linux artifacts are built inside an old-glibc container (see
# docs/building.md "Linux compatibility floor"). This script makes the result
# checkable: it reports the highest GLIBC_* symbol version a binary needs, and
# fails when it exceeds --max or when the binary depends on a shared library
# the archive does not ship.
#
# Usage:
#   src/prj/fun/check-linux-floor.sh funcmd libtcc.so
#   src/prj/fun/check-linux-floor.sh --max 2.17 funcmd
#   src/prj/fun/check-linux-floor.sh --max 2.17 --allow libz.so.1 funcmd
#   src/prj/fun/check-linux-floor.sh --json floor.json funcmd libtcc.so
#
# --json writes the measured result as {"glibc_floor": "2.17",
# "needed": ["libc.so.6"]} for capabilities.json, so the floor is visible to
# users instead of living only in CI logs.
#
# Exit status: 0 = within the floor and self-contained, 1 = violation,
#              2 = usage error.
#
# The default allowlist is the C runtime a Linux executable is expected to use.
# libpcre/libffi must not appear: the build links both statically so the
# artifact does not inherit the build host's sonames or glibc floor.
# ============================================================
set -u

max=""
allows="libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libgcc_s.so.1 libutil.so.1"
json=""
files=""

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --max)   [ $# -ge 2 ] || { usage >&2; exit 2; }; max="${2#GLIBC_}"; shift 2 ;;
        --allow) [ $# -ge 2 ] || { usage >&2; exit 2; }; allows="$allows $2"; shift 2 ;;
        --json)  [ $# -ge 2 ] || { usage >&2; exit 2; }; json="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "check-linux-floor: unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
files="$*"
[ -n "$files" ] || { usage >&2; exit 2; }

command -v objdump >/dev/null 2>&1 || { echo "check-linux-floor: objdump not found (install binutils)" >&2; exit 2; }
command -v readelf >/dev/null 2>&1 || { echo "check-linux-floor: readelf not found (install binutils)" >&2; exit 2; }

status=0
all_floor="none"
all_needed=""
for f in $files; do
    if [ ! -f "$f" ]; then
        echo "FAIL $f: not found"
        status=1
        continue
    fi

    vers="$(objdump -T "$f" 2>/dev/null | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/^GLIBC_//' | sort -Vu)"
    floor="$(printf '%s\n' "$vers" | tail -n 1)"
    [ -n "$floor" ] || floor="none"
    printf '%-30s glibc floor %s\n' "$f" "$floor"

    if [ -n "$max" ] && [ "$floor" != "none" ]; then
        higher="$(printf '%s\n%s\n' "$max" "$floor" | sort -V | tail -n 1)"
        if [ "$higher" != "$max" ]; then
            echo "  FAIL: requires GLIBC_$floor, above --max GLIBC_$max"
            status=1
        fi
        objdump -T "$f" 2>/dev/null | grep "GLIBC_$floor" \
            | awk '{print $NF}' | sort -u | head -n 3 | sed 's/^/  floor set by: /'
    fi

    needed="$(readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p')"
    all_needed="$all_needed $needed"
    if [ "$floor" != "none" ]; then
        if [ "$all_floor" = "none" ] || [ "$(printf '%s\n%s\n' "$floor" "$all_floor" | sort -V | tail -n 1)" = "$floor" ]; then
            all_floor="$floor"
        fi
    fi
    for lib in $needed; do
        ok=0
        for a in $allows; do
            if [ "$lib" = "$a" ]; then ok=1; break; fi
        done
        if [ "$ok" -eq 0 ]; then
            echo "  FAIL: NEEDED $lib is not self-contained (pass --allow to accept)"
            status=1
        fi
    done
done

if [ -n "$json" ]; then
    needed_json=""
    for lib in $(printf '%s\n' $all_needed | sort -u); do
        [ -n "$lib" ] || continue
        [ -z "$needed_json" ] || needed_json="$needed_json, "
        needed_json="$needed_json\"$lib\""
    done
    printf '{\n  "glibc_floor": "%s",\n  "needed": [%s]\n}\n' \
        "$all_floor" "$needed_json" > "$json"
    echo "wrote $json"
fi

if [ "$status" -eq 0 ]; then
    echo "floor check passed"
else
    echo "floor check FAILED" >&2
fi
exit "$status"
