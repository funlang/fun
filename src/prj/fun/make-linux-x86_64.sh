#!/bin/sh
# ============================================================
# Fun - 64-bit (x86_64) Linux console build of funcmd.dpr
#
# Counterpart of make-linux.bat (which cross-compiles i386 from a
# Windows-hosted FPC). This builds a native x86_64-linux interpreter.
#
# It also builds the bundled PCRE 8 engine (8-bit) from the vendored C source
# under src/3rd/pcre-8 (fetch PCRE 8.x from https://www.pcre.org/) and enables
# regex (-dRegex, one word - the "-dRegexx" used by the .bat scripts is a
# no-op typo). If the PCRE C source is not present, the build falls back to
# regex-disabled.
#
# It also builds the bundled Tiny C Compiler as libtcc.so from the vendored
# source under src/3rd/tcc (same version as the shipped Windows libtcc.dll,
# 0.9.27; fetch the tinycc release on savannah/nongnu or repo.or.cz tag
# release_0_9_27), drops it next to funcmd and links -rpath $ORIGIN so lib-tcc.fun's
# bare 'libtcc.so' resolves - the Linux counterpart of "DLL next to the .exe".
# Missing TCC source only disables runtime C compilation (lib-tcc.fun).
#
# -dMD5 enables the str.md5()/str.sha1() builtins. On Windows those wrap
# advapi32.dll; on Linux src/libmd5.inc now has a portable branch built on
# FPC's bundled md5/sha1 units (see the {$IfDef Linux} block there).
#
# -dFunPack enables "fun pack" and the single-file bundled-app runtime. The
# feature lives behind this define so a minimal FPC/Delphi build can omit it;
# the standard FPC build scripts turn it on. FUNPACK=user builds only the
# consumer runtime (-dFunPackUser): bundled apps run, but there is no
# "fun pack" subcommand.
#
# -dFunSafe enables the capability-restricted safe build. It is a separate
# binary, funcmd-safe, so the default build and its regression baseline stay
# unchanged. The level is selected with SAFE:
#   SAFE=strict    no file access, no native code, no compile-from-file
#   SAFE=readonly  also allow file reads (load/find/hash/size/time)
#   SAFE=readwrite also allow file writes (save/copy/move/time(set))
#   SAFE=custom    SAFE_ALLOW=read,write,compile
# See SAFETY.zh.md.
#
# Usage:
#   ./make-linux-x86_64.sh            # FPC resolved from PATH
#   FPC=/path/to/fpc ./make-linux-x86_64.sh
#   PCRE_SRC=/abs/path/to/pcre ./make-linux-x86_64.sh
#   TCC_SRC=/abs/path/to/tcc ./make-linux-x86_64.sh
#   SAFE=1 ./make-linux-x86_64.sh     # same as SAFE=strict
#   SAFE=readonly ./make-linux-x86_64.sh
#   SAFE=readwrite ./make-linux-x86_64.sh
#   SAFE=custom SAFE_ALLOW=read,compile ./make-linux-x86_64.sh
#
# Integer/double arithmetic, comparison, Boolean-result and integer div/mod
# fast paths (src/core/calc.inc) are on by default; they avoid the much slower
# Variant RTL for the common operand types. Set NO_CALC_OPT=1 to build without
# the CalcOpt-gated ones (useful for differential benchmarking; string concat
# and scalar assignment stay optimized). Extra FPC switches can still be
# appended:
#   ./make-linux-x86_64.sh -dFunTraceback  # opt-in: append a function traceback to
#                                         # runtime errors (a small per-call cost;
#                                         # the default build reports only file:line)
#   ./make-linux-x86_64.sh -dUseCThreads   # opt-in: link FPC's thread-safe heap
#                                         # (cthreads). Only needed when a C
#                                         # library calls a @toCallback closure
#                                         # from a pthread it created itself; it
#                                         # adds ~20% to every single-threaded
#                                         # run, so it is off by default.
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# --- Optional: refresh src/core/version.inc (written in Fun) ----------------
# The numeric version stamp is generated, not compiled in, so it only changes
# when you regenerate it. Off by default to keep builds reproducible; set
# FUN_GEN_VERSION=1 to run the generator first. The generator is a Fun script
# and needs a working interpreter, so this uses a previously built funcmd
# (the committed version.inc is used on a clean checkout).
if [ -n "$FUN_GEN_VERSION" ]; then
    PRE_FUNCMD="$(cd "$HERE/../../.." && pwd)/fun/funcmd"
    if [ -x "$PRE_FUNCMD" ]; then
        "$PRE_FUNCMD" "$HERE/gen-version.fun"
    else
        echo "FUN_GEN_VERSION set, but no prebuilt funcmd yet; skipping version regen" >&2
    fi
fi

# --- Resolve the Free Pascal driver ------------------------------
if [ -n "$FPC" ]; then
    FPC_BIN="$FPC"
elif command -v fpc >/dev/null 2>&1; then
    FPC_BIN="$(command -v fpc)"
elif [ -x /usr/bin/fpc ]; then
    FPC_BIN=/usr/bin/fpc
elif [ -x "$HOME/fpc-3.2.2/bin/fpc" ]; then
    FPC_BIN="$HOME/fpc-3.2.2/bin/fpc"
else
    echo "Free Pascal not found. Set FPC=<path-to-fpc-bin>." >&2
    exit 1
fi
FPC_BINDIR="$(dirname "$FPC_BIN")"
export PATH="$FPC_BINDIR:$PATH"

# --- Build bundled PCRE (8-bit) for Linux ------------------------
PCRE_SRC="${PCRE_SRC:-}"
if [ -z "$PCRE_SRC" ] && [ -d "$HERE/../../3rd/pcre-8" ]; then
    PCRE_SRC="$(cd "$HERE/../../3rd/pcre-8" && pwd)"
fi
PCRE_FLAGS=""
if [ -n "$PCRE_SRC" ] && [ -f "$PCRE_SRC/pcre_compile.c" ]; then
    PCRE_LIB="$PCRE_SRC/linux-lib"
    mkdir -p "$PCRE_LIB"
    # A pristine PCRE tarball is not build-ready: it ships config.h.generic /
    # pcre.h.generic and pcre_chartables.c.dist (the upstream ./configure output
    # for a default build is byte-identical to them). Create the build-ready
    # files from those copies so no autoconf is needed. pcre_default_tables.c is
    # a dftables-generated duplicate of the default_tables symbol already in
    # pcre_chartables.c, so it is optional (the loop skips missing sources).
    [ -f "$PCRE_SRC/config.h" ]          || cp "$PCRE_SRC/config.h.generic"          "$PCRE_SRC/config.h"          2>/dev/null || true
    [ -f "$PCRE_SRC/pcre.h" ]            || cp "$PCRE_SRC/pcre.h.generic"            "$PCRE_SRC/pcre.h"            2>/dev/null || true
    [ -f "$PCRE_SRC/pcre_chartables.c" ] || cp "$PCRE_SRC/pcre_chartables.c.dist"   "$PCRE_SRC/pcre_chartables.c" 2>/dev/null || true
    if command -v gcc >/dev/null 2>&1; then
        # SUPPORT_JIT builds the PCRE 8 JIT engine. pcre_study() then compiles
        # each pattern once and pcre_exec() runs the machine code it produced;
        # patterns the JIT declines transparently fall back to the interpreter.
        PCRE_CFLAGS="-O2 -fPIC -ffunction-sections -fdata-sections -DHAVE_CONFIG_H -DSUPPORT_PCRE8 -DSUPPORT_JIT"
        PCRE_STAMP="$PCRE_LIB/.buildflags"
        # Object files are not tracked and the per-file rule only compares
        # timestamps, so a flag change would otherwise leave stale objects.
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
                gcc -c $PCRE_CFLAGS -I"$PCRE_SRC" "$PCRE_SRC/$f.c" -o "$PCRE_LIB/$f.o"
            fi
        done
        rm -f "$PCRE_LIB/libpcre.a"
        ar rcs "$PCRE_LIB/libpcre.a" "$PCRE_LIB"/*.o
        # libgcc supplies __clear_cache on aarch64, where the PCRE JIT flushes
        # the instruction cache after generating code. Pass the archive path
        # from gcc so ld finds it without relying on its own search path; it is
        # harmless on x86_64.
        LIBGCC="$(gcc -print-libgcc-file-name 2>/dev/null)"
        if [ -n "$LIBGCC" ]; then LIBGCC_FLAG="-k$LIBGCC"; else LIBGCC_FLAG="-k-lgcc"; fi
        # FPC passes -k flags before the linker response file that names
        # libpcre.a, so an archive listed there is normally scanned too early
        # to satisfy a later reference. -u makes __clear_cache undefined from
        # the start, which pulls its member from libgcc regardless of order.
        PCRE_FLAGS="-dRegex -Fl$PCRE_LIB -k-lc $LIBGCC_FLAG -k--undefined=__clear_cache -k--gc-sections"
        echo "Regex enabled (PCRE 8)."
    else
        echo "gcc not found - building WITHOUT regex." >&2
    fi
else
    echo "PCRE C source not found - building WITHOUT regex." >&2
fi

# --- Build bundled TCC (libtcc.so) for Linux ----------------------
# lib-tcc.fun loads 'libtcc.dll' on Windows and 'libtcc.so' on Linux (see the
# host probe at the top of that module). We build the shared library from the
# vendored TCC source (same version as the shipped Windows DLL, 0.9.27), drop
# it next to funcmd, and link funcmd with -rpath $ORIGIN so the bare soname
# resolves there - the Linux analogue of Windows' "DLL next to the .exe".
TCC_SRC="${TCC_SRC:-}"
if [ -z "$TCC_SRC" ] && [ -d "$HERE/../../3rd/tcc" ]; then
    TCC_SRC="$(cd "$HERE/../../3rd/tcc" && pwd)"
fi
TCC_FLAGS=""
if [ -n "$TCC_SRC" ] && [ -f "$TCC_SRC/libtcc.c" ] && command -v gcc >/dev/null 2>&1; then
    TCC_LIB="$HERE/libtcc.so"
    TCC_BUILD="$TCC_SRC/build-linux"
    if [ ! -f "$TCC_LIB" ] || [ "$TCC_SRC/libtcc.c" -nt "$TCC_LIB" ]; then
        echo "Building TCC (libtcc.so) from $TCC_SRC"
        mkdir -p "$TCC_BUILD"
        # out-of-tree build; configure emits config.h/config.mak + a Makefile
        if [ ! -f "$TCC_BUILD/config.mak" ]; then
            ( cd "$TCC_BUILD" && "$TCC_SRC/configure" --extra-cflags="-fPIC" )
        fi
        ( cd "$TCC_BUILD" && make libtcc.so ) || { echo "TCC build failed" >&2; exit 1; }
        cp "$TCC_BUILD/libtcc.so" "$TCC_LIB"
    fi
    TCC_FLAGS="-k-rpath -k\$ORIGIN"
    echo "TCC enabled (libtcc.so next to funcmd, rpath \$ORIGIN)."
else
    echo "TCC C source not found - building WITHOUT runtime C compile (lib-tcc.fun needs libtcc.so)." >&2
fi

# --- Optional FFI: Fun getapi() on Linux via FPC's bundled libffi unit ---
FFI_FLAGS=""
FFI_PPU="$(find "$(dirname "$FPC_BINDIR")/lib" -type d -name libffi 2>/dev/null | head -n 1)"
if [ -n "$FFI_PPU" ] && [ -f "$FFI_PPU/ffi.ppu" ]; then
    FFI_LIBDIR="$HERE/.ffi"
    if ! ldconfig -p 2>/dev/null | grep -q 'libffi\.so '; then
        # no libffi.so (dev symlink); point -lffi at the runtime .so.N
        real="$(ldconfig -p 2>/dev/null | awk '/libffi\.so/{print $NF; exit}')"
        if [ -n "$real" ]; then
            mkdir -p "$FFI_LIBDIR"
            ln -sf "$real" "$FFI_LIBDIR/libffi.so"
            FFI_FLAGS="-dLinuxFFI -Fu$FFI_PPU -Fu$HERE/../../lib -Fl$FFI_LIBDIR"
        else
            echo "libffi runtime not found - building WITHOUT FFI (getapi disabled)." >&2
        fi
    else
        FFI_FLAGS="-dLinuxFFI -Fu$FFI_PPU -Fu$HERE/../../lib"
    fi
    [ -n "$FFI_FLAGS" ] && echo "FFI enabled (getapi via libffi)."
else
    echo "FPC libffi binding not found - building WITHOUT FFI (getapi disabled on Linux)." >&2
fi

# --- Build funcmd ------------------------------------------------
echo "Building funcmd with $FPC_BIN"
CALC_FLAGS="-dCalcOpt"
if [ -n "${NO_CALC_OPT:-}" ]; then
    CALC_FLAGS=""
    echo "NO_CALC_OPT set - building without arithmetic fast paths."
fi
PACK_FLAGS="-dFunPack"
if [ "${FUNPACK:-}" = "user" ]; then
    PACK_FLAGS="-dFunPackUser"
    echo "FUNPACK=user - building only the bundled-app consumer."
fi
SAFE_FLAGS=""
SAFE_OUT=""
SAFE_LEVEL=""
SAFE_ALLOW_OPT="${SAFE_ALLOW:-}"
SAFE_ALLOW=""
case "${SAFE:-}" in
    ""|0|no|off) ;;
    1|strict)     SAFE_LEVEL=strict ;;
    read|readonly) SAFE_LEVEL=readonly; SAFE_ALLOW="read" ;;
    fs|rw|readwrite|read-write)
                  SAFE_LEVEL=readwrite; SAFE_ALLOW="read,write" ;;
    custom)       SAFE_LEVEL=custom; SAFE_ALLOW="$SAFE_ALLOW_OPT" ;;
    *)            echo "Unknown SAFE='$SAFE' (use strict, readonly, readwrite or custom)." >&2
                  exit 2 ;;
esac
if [ -n "$SAFE_LEVEL" ]; then
    SAFE_FLAGS="-dFunSafe"
    SAFE_OUT="-o$HERE/funcmd-safe"
    SAFE_ALLOW="$(printf '%s' "$SAFE_ALLOW" | tr -d '[:space:]')"
    OLDIFS="$IFS"
    IFS=','
    for cap in $SAFE_ALLOW; do
        case "$cap" in
            read)    SAFE_FLAGS="$SAFE_FLAGS -dFunSafeAllowRead" ;;
            write)   SAFE_FLAGS="$SAFE_FLAGS -dFunSafeAllowWrite" ;;
            compile) SAFE_FLAGS="$SAFE_FLAGS -dFunSafeAllowCompile" ;;
            "")      ;;
            *)       echo "Unknown SAFE_ALLOW capability '$cap' (use read, write, compile)." >&2
                     exit 2 ;;
        esac
    done
    IFS="$OLDIFS"
    echo "SAFE=$SAFE_LEVEL${SAFE_ALLOW:+ (allow: $SAFE_ALLOW)} - building funcmd-safe."
fi
# Keep the two modes' .ppu/.o files apart. FPC otherwise writes units into the
# current directory, and a later build of the other mode can silently reuse
# them (normal code leaking into safe, or safe checks leaking into normal).
if [ -n "$SAFE_LEVEL" ]; then
    UNITS="$HERE/units-safe"
else
    UNITS="$HERE/units"
fi
mkdir -p "$UNITS"
UNIT_FLAGS="-FU$UNITS"
# FPC's -B does not rebuild units when only -d defines change, and the safe
# levels differ only by defines. Clearing the mode's unit cache keeps a
# SAFE=readonly build from reusing SAFE=strict units (and vice versa). A full
# build is about a second.
rm -f "$UNITS"/*.ppu "$UNITS"/*.o "$UNITS"/*.or 2>/dev/null || true
# shellcheck disable=SC2086
"$FPC_BIN" funcmd.dpr -B -Sd -O2 -Xs -XX -CX -Tlinux -dLinux -dMD5 $PACK_FLAGS $CALC_FLAGS $SAFE_FLAGS $SAFE_OUT $UNIT_FLAGS $PCRE_FLAGS $TCC_FLAGS $FFI_FLAGS "$@"

# --- Convenience copy into fun/ (the runtime folder) -------------
# Refresh fun/funcmd on every build, so a run from the repo root is just
#   fun/funcmd fun/demo/input.fun
# without reaching into src/prj/fun. funcmd is linked with -rpath $ORIGIN, so
# the copy needs libtcc.so beside it as well. Deliberately NOT the repo root:
# keep the root clean and the binaries with the demo/ and lib/ they drive.
ROOT="$(cd "$HERE/../../.." && pwd)"
if [ -n "$SAFE_LEVEL" ]; then
    BUILD_BIN="$HERE/funcmd-safe"
    TARGET_BIN="$ROOT/fun/funcmd-safe"
else
    BUILD_BIN="$HERE/funcmd"
    TARGET_BIN="$ROOT/fun/funcmd"
fi
if [ -f "$BUILD_BIN" ] && [ -d "$ROOT/fun" ]; then
    cp -f "$BUILD_BIN" "$TARGET_BIN"
    if [ -f "$HERE/libtcc.so" ]; then
        cp -f "$HERE/libtcc.so" "$ROOT/fun/libtcc.so"
    fi
    echo "Copied $(basename "$BUILD_BIN") to $TARGET_BIN"
fi
