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
#   CC="$ZIG cc" TCC_TARGET_FLAGS="-target aarch64-macos" \
#       ./build-tcc-darwin.sh arm64 /path/to/libtcc.dylib
#
# Inputs:
#   TCC_SRC          TCC source tree (default: ../../3rd/tcc)
#   CC               C compiler command (default: cc); may contain arguments
#   TCC_TARGET_FLAGS extra compiler/linker flags (e.g. -target x86_64-macos)
#
# x86_64 builds TCC directly. arm64 first applies patches/tcc-darwin-arm64.patch,
# which adds the __darwin_arm_thread_state64 field names and MAP_JIT /
# pthread_jit_write_protect_np handling that TCC 0.9.27 lacks.
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
    arm64|aarch64) ARCH=arm64 ;;
    *) echo "build-tcc-darwin: unsupported arch '$ARCH'" >&2; exit 2 ;;
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
if [ "$ARCH" = arm64 ]; then
    FILES="libtcc tccpp tccgen tccelf tccasm tccrun arm64-gen arm64-link"
    DEFS="-DTCC_TARGET_ARM64 -DTCC_TARGET_MACHO -DONE_SOURCE=0"
else
    FILES="libtcc tccpp tccgen tccelf tccasm tccrun x86_64-gen x86_64-link i386-asm"
    DEFS="-DTCC_TARGET_X86_64 -DTCC_TARGET_MACHO -DONE_SOURCE=0"
fi

SRC="$TCC_SRC"
if [ "$ARCH" = arm64 ]; then
    PATCH="$HERE/patches/tcc-darwin-arm64.patch"
    [ -f "$PATCH" ] || { echo "build-tcc-darwin: missing $PATCH" >&2; exit 1; }
    # Keep src/3rd pristine: patch a private copy so repeated builds and the
    # shared third-party cache never depend on the order they ran in.
    cp -R "$TCC_SRC" "$TMP/tcc"
    SRC="$TMP/tcc"
    ( cd "$SRC" && patch -p1 -s < "$PATCH" ) || {
        echo "build-tcc-darwin: could not apply $PATCH" >&2
        exit 1
    }
fi

for f in $FILES; do
    # shellcheck disable=SC2086
    $CC $TCC_TARGET_FLAGS -c -O2 -fPIC -I"$TMP" -I"$SRC" $DEFS \
        "$SRC/$f.c" -o "$TMP/$f.o"
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
