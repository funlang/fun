#!/bin/sh
# ============================================================
# build-tcc-darwin.sh -- build libtcc.dylib for macOS.
#
# Native use (on a Mac):
#   ./build-tcc-darwin.sh x86_64 ../libtcc.dylib
#
# Cross use (Linux x86_64, with Zig):
#   CC="$ZIG cc" TCC_TARGET_FLAGS="-target x86_64-macos" \
#       ./build-tcc-darwin.sh x86_64 /path/to/libtcc.dylib
#
# Inputs:
#   TCC_SRC          TCC source tree (default: ../../3rd/tcc)
#   CC               C compiler command (default: cc); may contain arguments
#   TCC_TARGET_FLAGS extra compiler/linker flags (e.g. -target x86_64-macos)
#
# Only x86_64 is enabled for now. The arm64 backend needs two pieces that
# TCC 0.9.27 does not provide for Darwin: __darwin_arm_thread_state64 field
# names in tccrun.c and MAP_JIT / pthread_jit_write_protect_np handling for
# Apple Silicon. Keep this script as the single build entry point when that
# work starts, so make-macos.sh does not grow another platform branch.
# ============================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ARCH="${1:-$(uname -m)}"
OUT="${2:-$HERE/libtcc.dylib}"
TCC_SRC="${TCC_SRC:-$HERE/../../3rd/tcc}"
CC="${CC:-cc}"
TCC_TARGET_FLAGS="${TCC_TARGET_FLAGS:-}"

case "$ARCH" in
    x86_64|amd64) ARCH=x86_64 ;;
    *)
        echo "build-tcc-darwin: unsupported arch '$ARCH' (only x86_64 is enabled)" >&2
        echo "  arm64 needs the TCC ucontext and MAP_JIT changes described in the header" >&2
        exit 2
        ;;
esac

if [ ! -f "$TCC_SRC/libtcc.c" ]; then
    echo "build-tcc-darwin: TCC source not found at $TCC_SRC" >&2
    exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fun-tcc-darwin.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

# tcc.h includes config.h. The configure script normally generates a much
# larger file, but a dylib used with -nostdlib -nostdinc only needs the version
# string (same approach as build-win64-deps.sh).
printf '#define TCC_VERSION "0.9.27"\n' > "$TMP/config.h"

# libtcc's Unix objects; tcc.c/tcctools.c are the command-line front end and
# are not part of the library.
FILES="libtcc tccpp tccgen tccelf tccasm tccrun x86_64-gen x86_64-link i386-asm"
DEFS="-DTCC_TARGET_X86_64 -DTCC_TARGET_MACHO -DONE_SOURCE=0"

for f in $FILES; do
    # shellcheck disable=SC2086
    $CC $TCC_TARGET_FLAGS -c -O2 -fPIC -I"$TMP" -I"$TCC_SRC" $DEFS \
        "$TCC_SRC/$f.c" -o "$TMP/$f.o"
done

mkdir -p "$(dirname "$OUT")"
# shellcheck disable=SC2086
$CC $TCC_TARGET_FLAGS -dynamiclib -o "$OUT" "$TMP"/*.o -lm \
    -Wl,-install_name,@rpath/libtcc.dylib

# The Fun module calls these with getapi(); a missing export must fail the
# build rather than surface as a nil handle at run time. GNU nm cannot read
# Mach-O, so only enforce this on a real Mac (or when the host nm supports it).
if [ "$(uname -s)" = Darwin ]; then
    missing=""
    for sym in tcc_new tcc_delete tcc_set_error_func tcc_set_options \
               tcc_compile_string tcc_relocate tcc_get_symbol; do
        nm -gU "$OUT" 2>/dev/null | grep -q "_$sym\$" || missing="$missing $sym"
    done
    [ -z "$missing" ] || {
        echo "build-tcc-darwin: missing exports:$missing" >&2
        exit 1
    }
fi

echo "built $OUT ($(wc -c < "$OUT") bytes)"
