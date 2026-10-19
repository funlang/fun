#!/bin/sh
# ============================================================
# Fun - native macOS (Darwin) console build of funcmd.dpr
#
# Counterpart of make-linux-x86_64.sh, for a real Mac (Apple Silicon or Intel)
# with a native Free Pascal. The cross-compiled equivalent, which runs on a
# Linux build machine, is make-darwin.sh; this script is what a macos-latest CI
# runner (or a developer on a Mac) uses.
#
# It builds the bundled PCRE 8 engine (regex) and enables getapi() via FPC's
# bundled libffi unit when both are available; otherwise it degrades and prints
# a notice (regex / getapi off), exactly like the Linux script.
#
# Not built on macOS: libtcc.dylib (no macOS build of the vendored TCC yet), so
# lib-tcc.fun / lib-jit.fun stay unavailable and their tests are skipped.
#
# Usage:
#   ./make-macos.sh                 # FPC from PATH, or /usr/local/bin, /opt/homebrew/bin
#   FPC=/path/to/fpc ./make-macos.sh
#   PCRE_SRC=/abs/path/to/pcre ./make-macos.sh
#   ./make-macos.sh -dFunTraceback  # extra FPC switches are appended
#
# Root privilege is never needed and no Apple SDK download is required.
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# --- Resolve the Free Pascal driver --------------------------------------
if [ -n "${FPC:-}" ]; then
    FPC_BIN="$FPC"
elif command -v fpc >/dev/null 2>&1; then
    FPC_BIN="$(command -v fpc)"
elif [ -x /opt/homebrew/bin/fpc ]; then
    FPC_BIN=/opt/homebrew/bin/fpc
elif [ -x /usr/local/bin/fpc ]; then
    FPC_BIN=/usr/local/bin/fpc
else
    echo "Free Pascal not found. Install it (e.g. 'brew install fpc') or set FPC=<path-to-fpc-bin>." >&2
    exit 1
fi
FPC_BINDIR="$(dirname "$FPC_BIN")"
export PATH="$FPC_BINDIR:$PATH"

# FPC keeps its compiled units under a prefix that Homebrew splits from bin/
# (e.g. /opt/homebrew/bin/fpc -> /opt/homebrew/Cellar/fpc/3.2.2/lib/fpc/...).
# Probe the usual roots instead of resolving the symlink (macOS readlink has no
# -f). Only used to locate optional units (libffi); the standard units are found
# through FPC's own fpc.cfg.
find_unit_dir() {
    name="$1"
    for root in "$(dirname "$FPC_BINDIR")/lib" \
                /opt/homebrew/lib /usr/local/lib \
                /opt/homebrew/Cellar /usr/local/Cellar; do
        d="$(find "$root" -type d -name "$name" 2>/dev/null | head -n 1)"
        if [ -n "$d" ]; then printf '%s\n' "$d"; return 0; fi
    done
    return 1
}

# --- Optional: bundled PCRE 8 (regex) ------------------------------------
PCRE_SRC="${PCRE_SRC:-$(cd "$HERE/../../3rd/pcre-8" 2>/dev/null && pwd)}"
PCRE_FLAGS=""
if [ -n "$PCRE_SRC" ] && [ -f "$PCRE_SRC/pcre_compile.c" ]; then
    if ! command -v cc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
        echo "no C compiler - building WITHOUT regex." >&2
    else
        CC="$(command -v cc || command -v clang)"
        PCRE_LIB="$PCRE_SRC/darwin-lib"
        mkdir -p "$PCRE_LIB"
        # A pristine PCRE tarball is not build-ready: create the generated files
        # from the .generic / .dist copies it ships (see make-linux-x86_64.sh).
        [ -f "$PCRE_SRC/config.h" ]          || cp "$PCRE_SRC/config.h.generic"          "$PCRE_SRC/config.h"          2>/dev/null || true
        [ -f "$PCRE_SRC/pcre.h" ]            || cp "$PCRE_SRC/pcre.h.generic"            "$PCRE_SRC/pcre.h"            2>/dev/null || true
        [ -f "$PCRE_SRC/pcre_chartables.c" ] || cp "$PCRE_SRC/pcre_chartables.c.dist"   "$PCRE_SRC/pcre_chartables.c" 2>/dev/null || true
        # SUPPORT_JIT builds the PCRE 8 JIT engine; see make-linux-x86_64.sh.
        PCRE_CFLAGS="-O2 -fPIC -ffunction-sections -fdata-sections -DHAVE_CONFIG_H -DSUPPORT_PCRE8 -DSUPPORT_JIT"
        PCRE_STAMP="$PCRE_LIB/.buildflags"
        if [ ! -f "$PCRE_STAMP" ] || [ "$(cat "$PCRE_STAMP" 2>/dev/null)" != "$PCRE_CFLAGS" ]; then
            rm -f "$PCRE_LIB"/*.o "$PCRE_LIB/libpcre.a"
            printf '%s\n' "$PCRE_CFLAGS" > "$PCRE_STAMP"
        fi
        echo "Building PCRE 8 from $PCRE_SRC (with JIT)"
        for f in pcre_byte_order pcre_chartables pcre_compile pcre_config \
                 pcre_default_tables pcre_dfa_exec pcre_exec pcre_fullinfo \
                 pcre_get pcre_globals pcre_jit_compile pcre_maketables pcre_newline \
                 pcre_ord2utf8 pcre_refcount pcre_study pcre_tables pcre_ucd \
                 pcre_valid_utf8 pcre_version pcre_xclass pcre_string_utils; do
            [ -f "$PCRE_SRC/$f.c" ] || continue
            if [ ! -f "$PCRE_LIB/$f.o" ] || [ "$PCRE_SRC/$f.c" -nt "$PCRE_LIB/$f.o" ]; then
                # shellcheck disable=SC2086
                "$CC" -c $PCRE_CFLAGS -I"$PCRE_SRC" "$PCRE_SRC/$f.c" -o "$PCRE_LIB/$f.o"
            fi
        done
        rm -f "$PCRE_LIB/libpcre.a"
        ar rcs "$PCRE_LIB/libpcre.a" "$PCRE_LIB"/*.o
        PCRE_FLAGS="-dRegex -Fl$PCRE_LIB"
        echo "Regex enabled (PCRE 8)."
    fi
else
    echo "PCRE C source not found - building WITHOUT regex." >&2
fi

# --- Optional: getapi() via FPC's bundled libffi unit --------------------
# The engine maps -dDarwinFFI to its UnixFFI symbol; libffi itself is part of
# libSystem on macOS, so only FPC's 'ffi' unit has to be locatable.
FFI_FLAGS=""
FFI_PPU="$(find_unit_dir libffi || true)"
if [ -n "$FFI_PPU" ] && [ -f "$FFI_PPU/ffi.ppu" ]; then
    FFI_FLAGS="-dDarwinFFI -Fu$FFI_PPU -Fu$HERE/../../lib"
    echo "FFI enabled (getapi via libffi)."
else
    echo "FPC libffi unit (ffi.ppu) not found - building WITHOUT getapi (FFI disabled on macOS)." >&2
fi

# --- Build funcmd --------------------------------------------------------
echo "Building funcmd with $FPC_BIN"
# shellcheck disable=SC2086
"$FPC_BIN" funcmd.dpr -B -Sd -O2 -Xs -XX -CX -dMD5 -dFunPack $PCRE_FLAGS $FFI_FLAGS "$@"

# --- Convenience copy into fun/ (the runtime folder) ---------------------
ROOT="$(cd "$HERE/../../.." && pwd)"
if [ -f "$HERE/funcmd" ] && [ -d "$ROOT/fun" ]; then
    cp -f "$HERE/funcmd" "$ROOT/fun/funcmd"
    echo "Copied funcmd to $ROOT/fun/funcmd"
fi
