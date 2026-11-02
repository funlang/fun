# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# safe-flags.sh -- shared SAFE=... parser for the POSIX build scripts.
#
# Sourced, never executed:
#
#   . "$HERE/safe-flags.sh"
#   fun_safe_parse || exit 2
#
# On return:
#   FUN_SAFE_LEVEL  strict|readonly|readwrite|custom, or empty (normal build)
#   FUN_SAFE_FLAGS  -dFunSafe plus the allowed -dFunSafeAllow* macros
#   FUN_SAFE_ALLOW  normalized "read,write,compile" (diagnostics only)
#
# An empty / 0 / no / off SAFE leaves all three empty. The define set is
# platform independent: the same macros drive the checks in src/core,
# src/lib and src/parse on every target.

fun_safe_parse() {
    FUN_SAFE_LEVEL=""
    FUN_SAFE_FLAGS=""
    FUN_SAFE_ALLOW=""
    case "${SAFE:-}" in
        ""|0|no|off) return 0 ;;
        1|strict)     FUN_SAFE_LEVEL=strict ;;
        read|readonly) FUN_SAFE_LEVEL=readonly; FUN_SAFE_ALLOW=read ;;
        fs|rw|readwrite|read-write)
                      FUN_SAFE_LEVEL=readwrite; FUN_SAFE_ALLOW=read,write ;;
        custom)       FUN_SAFE_LEVEL=custom; FUN_SAFE_ALLOW="${SAFE_ALLOW:-}" ;;
        *)            echo "Unknown SAFE='$SAFE' (use strict, readonly, readwrite or custom)." >&2
                      return 2 ;;
    esac
    FUN_SAFE_FLAGS="-dFunSafe"
    FUN_SAFE_ALLOW="$(printf '%s' "$FUN_SAFE_ALLOW" | tr -d '[:space:]')"
    OLDIFS="$IFS"
    IFS=','
    for cap in $FUN_SAFE_ALLOW; do
        case "$cap" in
            read)    FUN_SAFE_FLAGS="$FUN_SAFE_FLAGS -dFunSafeAllowRead" ;;
            write)   FUN_SAFE_FLAGS="$FUN_SAFE_FLAGS -dFunSafeAllowWrite" ;;
            compile) FUN_SAFE_FLAGS="$FUN_SAFE_FLAGS -dFunSafeAllowCompile" ;;
            "")      ;;
            *)       echo "Unknown SAFE_ALLOW capability '$cap' (use read, write, compile)." >&2
                     IFS="$OLDIFS"
                     return 2 ;;
        esac
    done
    IFS="$OLDIFS"
    echo "SAFE=$FUN_SAFE_LEVEL${FUN_SAFE_ALLOW:+ (allow: $FUN_SAFE_ALLOW)} - building funcmd-safe."
    return 0
}
