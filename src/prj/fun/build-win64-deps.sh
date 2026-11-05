#!/bin/sh
# ============================================================
# build-win64-deps.sh -- build the 64-bit runtime DLLs for Windows.
#
#   libtcc.dll   runtime C compilation (lib-tcc.fun / NewJit C path)
#   zlib.dll     lib-zlib.fun (HTTP gzip, WebSocket deflate, asm lists)
#
# Both are loaded by bare name from next to fun.exe, so the release archive
# must ship x86_64 DLLs. The copies historically carried in fun/ are 32-bit
# bcc32 builds: a win64 fun.exe cannot load those, which is why runtime C and
# zlib used to be reported as missing on win-x64.
#
# This script does not use TCC's or zlib's makefiles. It compiles the pinned
# sources directly, so it works on Linux (cross compiler) and on the Windows
# CI runner (MinGW-w64 gcc) with the same argument list.
#
# Usage:
#   CC=x86_64-w64-mingw32-gcc ./build-win64-deps.sh
#   CC=/c/msys64/mingw64/bin/gcc.exe ZLIB_SRC=/path/to/zlib-1.2.11 \
#       ./build-win64-deps.sh
#
# Env:
#   CC             C compiler targeting x86_64-w64-mingw32 (required)
#   TCC_SRC        TCC source tree        (default: src/3rd/tcc)
#   ZLIB_SRC       zlib source tree       (default: src/3rd/zlib,
#                                          src/3rd/zlib-1.2.11, or $ZLIB_SRC)
#   OUT            output directory       (default: this script's directory)
#   STRIP/NM       optional binutils      (found next to CC by default)
#
# A missing zlib source is not fatal: libtcc.dll is still built and the caller
# reports zlib as unavailable.
# ============================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
OUT="${OUT:-$HERE}"
TCC_SRC="${TCC_SRC:-$ROOT/src/3rd/tcc}"
ZLIB_SRC="${ZLIB_SRC:-}"
if [ -z "$ZLIB_SRC" ]; then
    for d in "$ROOT/src/3rd/zlib" "$ROOT/src/3rd/zlib-1.2.11" "$ROOT/src/3rd/zlib-1.2.11/zlib-1.2.11"; do
        if [ -f "$d/zlib.h" ] && [ -f "$d/deflate.c" ]; then ZLIB_SRC="$d"; break; fi
    done
fi

if [ -z "$CC" ]; then
    echo "build-win64-deps: set CC to an x86_64-w64-mingw32 C compiler" >&2
    exit 2
fi
if ! command -v "$CC" >/dev/null 2>&1; then
    echo "build-win64-deps: compiler not found: $CC" >&2
    exit 2
fi

CCDIR="$(dirname "$CC")"
tool() {
    # tool <name> <fallback>
    if [ -n "$1" ] && command -v "$1" >/dev/null 2>&1; then printf '%s' "$1"; return 0; fi
    for cand in "$CCDIR/x86_64-w64-mingw32-$2" "$CCDIR/$2"; do
        if [ -x "$cand" ]; then printf '%s' "$cand"; return 0; fi
    done
    return 1
}
NM="$(tool "${NM:-}" nm || true)"
OBJDUMP="$(tool "${OBJDUMP:-}" objdump || true)"
STRIP="$(tool "${STRIP:-}" strip || true)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fun-win64-deps-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM
mkdir -p "$OUT"

# --- libtcc.dll -----------------------------------------------------------
if [ ! -f "$TCC_SRC/libtcc.c" ]; then
    echo "build-win64-deps: TCC source not found at $TCC_SRC" >&2
    exit 1
fi
echo "building libtcc.dll from $TCC_SRC"
# tcc.h includes config.h, which the upstream configure script normally
# generates in the build directory. Only the version is needed for a DLL that
# is always used with -nostdlib -nostdinc (see lib-tcc.fun).
printf '#define TCC_VERSION "0.9.27"\n' > "$TMP/config.h"
# The set is the one TCC's Makefile links for a 64-bit Windows DLL
# (LIBTCC_AS_DLL exports the tcc_* API). ONE_SOURCE=0 keeps the per-file
# objects; tccpe.c supplies the PE back end.
TCC_FILES="libtcc tccpp tccgen tccelf tccasm tccrun x86_64-gen x86_64-link i386-asm tccpe"
for f in $TCC_FILES; do
    "$CC" -c -O2 -I"$TMP" -I"$TCC_SRC" \
        -DTCC_TARGET_X86_64 -DTCC_TARGET_PE -DLIBTCC_AS_DLL -DONE_SOURCE=0 \
        "$TCC_SRC/$f.c" -o "$TMP/$f.o"
done
"$CC" -shared -static -o "$OUT/libtcc.dll" "$TMP"/libtcc.o "$TMP"/tccpp.o \
    "$TMP"/tccgen.o "$TMP"/tccelf.o "$TMP"/tccasm.o "$TMP"/tccrun.o \
    "$TMP"/x86_64-gen.o "$TMP"/x86_64-link.o "$TMP"/i386-asm.o "$TMP"/tccpe.o
if [ -n "$NM" ]; then
    for sym in tcc_new tcc_delete tcc_compile_string tcc_relocate tcc_get_symbol; do
        if ! "$NM" -g --defined-only "$OUT/libtcc.dll" 2>/dev/null | tr -d '\r' | grep -q " $sym\$"; then
            echo "build-win64-deps: libtcc.dll is missing export $sym" >&2
            exit 1
        fi
    done
fi
if [ -n "$STRIP" ]; then "$STRIP" --strip-unneeded "$OUT/libtcc.dll" || true; fi
echo "built $OUT/libtcc.dll ($(wc -c < "$OUT/libtcc.dll") bytes)"

# --- zlib.dll -------------------------------------------------------------
if [ -z "$ZLIB_SRC" ] || [ ! -f "$ZLIB_SRC/deflate.c" ]; then
    echo "build-win64-deps: zlib source not found; skipping zlib.dll" >&2
    echo "  fetch it into src/3rd/zlib-1.2.11 (fetch-3rd-party.sh) or set ZLIB_SRC" >&2
    exit 0
fi
echo "building zlib.dll from $ZLIB_SRC"
# zlib 1.2.11 sources used by its win32 shared build. ZLIB_DLL is what makes
# zlib.h mark the API __declspec(dllexport) while compiling the DLL.
ZLIB_FILES="adler32 compress crc32 deflate gzclose gzlib gzread gzwrite \
infback inffast inflate inftrees trees uncompr zutil"
for f in $ZLIB_FILES; do
    "$CC" -c -O2 -DZLIB_DLL -I"$ZLIB_SRC" "$ZLIB_SRC/$f.c" -o "$TMP/z-$f.o"
done
"$CC" -shared -static -o "$OUT/zlib.dll" "$TMP"/z-*.o
if [ -n "$STRIP" ]; then "$STRIP" --strip-unneeded "$OUT/zlib.dll" || true; fi
if [ -n "$OBJDUMP" ]; then
    for sym in compress uncompress deflateInit2_ inflateInit2_ zlibVersion; do
        if ! "$OBJDUMP" -p "$OUT/zlib.dll" 2>/dev/null | tr -d '\r' | grep -q "\[.*\] $sym\$"; then
            echo "build-win64-deps: zlib.dll is missing export $sym" >&2
            exit 1
        fi
    done
fi
echo "built $OUT/zlib.dll ($(wc -c < "$OUT/zlib.dll") bytes)"
