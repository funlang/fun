#!/bin/sh
# ============================================================
# make-linux-riscv64.sh -- cross-build funcmd.dpr for Linux riscv64
# from an x86_64 Linux host. Counterpart of make-linux-aarch64.sh.
#
# FPC's riscv64-linux target is still on main/3.3.1. Run
# bootstrap-linux-riscv64.sh first; it produces the cross compiler, the
# RTL/rtl-objpas/hash units and the GNU binutils shims used here.
#
# Current capability boundary (same as the aarch64 cross artifact):
#   - core interpreter + portable standard library: yes
#   - regex: no in the default build. The bundled PCRE is C and needs a target
#     libc; FULL=1 with the Alpine sysroot provides it.
#   - FFI (getapi): no in the default build. Needs a riscv64 libffi;
#     FULL=1 provides it.
#   - TinyCC / #!c: no. TinyCC has no riscv64 backend.
#   - lib-asm / #!asm: yes. lib-asm-riscv64 encodes the RV64IM base set plus
#     Zicsr/Zifencei; JIT calls work on riscv64 hosts and under qemu-user.
# The build is still useful for running the language, demos and the portable
# stdlib under qemu or on real RISC-V hardware.
#
# Usage:
#   ./make-linux-riscv64.sh
#   RISCV_FPC_ROOT=/opt/riscv ./make-linux-riscv64.sh
#   FUN_THREADS=1 FULL=1 ./make-linux-riscv64.sh   # funcmd-mt (worker model)
#   ./make-linux-riscv64.sh -dMyFlag ...   # extra FPC switches
#
# Needs: bootstrap-linux-riscv64.sh run first (or RISCV_FPC_ROOT pointing
# at its output).
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

ROOT="${RISCV_FPC_ROOT:-$HOME/.fun/linux-riscv64}"
PPCROSS="${RISCV_PPCROSS:-$ROOT/bin/ppcrossriscv64}"
FULL="${FULL:-0}"
SYSROOT="${RISCV_SYSROOT:-}"

if [ "$FULL" = "1" ]; then
    UNITS="${RISCV_UNITS:-$ROOT/units-libc/riscv64-linux}"
    UNITS_OBJPAS="${RISCV_UNITS_OBJPAS:-$ROOT/units-objpas-libc/riscv64-linux}"
    UNITS_HASH="${RISCV_UNITS_HASH:-$ROOT/units-hash-libc/riscv64-linux}"
    UNITS_FFI="${RISCV_UNITS_FFI:-$ROOT/units-ffi/riscv64-linux}"
else
    UNITS="${RISCV_UNITS:-$ROOT/units/riscv64-linux}"
    UNITS_OBJPAS="${RISCV_UNITS_OBJPAS:-$ROOT/units-objpas/riscv64-linux}"
    UNITS_HASH="${RISCV_UNITS_HASH:-$ROOT/units-hash/riscv64-linux}"
    UNITS_FFI=""
fi
TOOLS="${RISCV_TOOLS:-$ROOT/tools}"

[ -x "$PPCROSS" ]  || { echo "ppcrossriscv64 not found: $PPCROSS" >&2
                        echo "Run bootstrap-linux-riscv64.sh first." >&2; exit 1; }
[ -f "$UNITS/system.ppu" ] || { echo "riscv64-linux units not found: $UNITS" >&2
                                echo "Run bootstrap-linux-riscv64.sh first." >&2; exit 1; }
[ -x "$TOOLS/riscv64-linux-as" ] || { echo "assembler not found under $TOOLS" >&2; exit 1; }
[ -x "$TOOLS/riscv64-linux-ld" ] || { echo "linker not found under $TOOLS" >&2; exit 1; }

LINK_FLAGS=""
if [ "$FULL" = "1" ]; then
    [ -n "$SYSROOT" ] || { echo "FULL=1 needs RISCV_SYSROOT (see prepare-linux-riscv64-sysroot.sh)" >&2; exit 1; }
    [ -f "$UNITS_FFI/ffi.ppu" ] || { echo "libffi binding not found: $UNITS_FFI/ffi.ppu" >&2
                                     echo "Run bootstrap-linux-riscv64.sh with FPC_USE_LIBC=1." >&2; exit 1; }
    [ -f "$SYSROOT/lib/ld-musl-riscv64.so.1" ] || { echo "musl sysroot not found: $SYSROOT" >&2; exit 1; }
    LINK_FLAGS="-Fl$SYSROOT/usr/lib -Fl$SYSROOT/lib -k-lc -k-lpcre -k-lffi -k-ldl"
fi

# SAFE=... builds a capability-restricted variant (the fresh temp unit dir keeps
# the modes apart; same macros as make-linux-x86_64.sh).
. "$HERE/safe-flags.sh"
fun_safe_parse || exit 2

if [ "${FUNPACK:-}" = "user" ]; then
    FEATURES="-dFunPackUser"
else
    FEATURES="-dFunPack"
fi
FEATURES="$FEATURES $FUN_SAFE_FLAGS"
# Call-site traceback and the runtime frame ring are on by default. Set
# FUN_TRACEBACK=0 to build without the bookkeeping.
if [ "${FUN_TRACEBACK:-1}" = "0" ]; then
    echo "FUN_TRACEBACK=0 - building without the call ring."
else
    FEATURES="$FEATURES -dFunTraceback"
fi
if [ "$FULL" = "1" ]; then
    FEATURES="$FEATURES -dRegex -dLinuxFFI -dFPC_USE_LIBC"
fi

FU_EXTRA=""
if [ -f "$UNITS_HASH/md5.ppu" ] && [ -f "$UNITS_HASH/sha1.ppu" ]; then
    FEATURES="$FEATURES -dMD5"
    FU_EXTRA="$FU_EXTRA -Fu$UNITS_HASH"
    echo "MD5/SHA1 enabled."
else
    echo "md5/sha1 units not found - building without -dMD5." >&2
fi
[ -d "$UNITS_OBJPAS" ] && FU_EXTRA="$FU_EXTRA -Fu$UNITS_OBJPAS"
[ -n "$UNITS_FFI" ] && FU_EXTRA="$FU_EXTRA -Fu$UNITS_FFI"
if [ "$FULL" = "1" ] || [ "${FUN_THREADS:-0}" = "1" ]; then
    FU_EXTRA="$FU_EXTRA -Fu$HERE/../../lib"
fi

# -dFunNoRes: the cross toolchain has no riscv64 fpcres, so skip the
# Windows version resource. It is not used on Linux.
FEATURES="$FEATURES -dFunNoRes"

# FUN_THREADS=1 builds funcmd-mt (the worker model). Unix needs the
# cthreads unit for the thread-safe heap; it comes from the RTL units that
# bootstrap-linux-riscv64.sh installs.
MT_FLAGS=""
MT_SUFFIX=""
if [ "${FUN_THREADS:-0}" = "1" ]; then
    [ -f "$UNITS/cthreads.ppu" ] || {
        echo "FUN_THREADS=1 needs $UNITS/cthreads.ppu; rerun the bootstrap." >&2
        exit 1
    }
    MT_FLAGS="-dFunThreads -dUseCThreads"
    MT_SUFFIX="-mt"
fi

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/fun-lin-riscv-build-XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
echo "Building funcmd for linux/riscv64 with $PPCROSS"
# -n: ignore the host fpc.cfg
# -XP: FPC's cross prefix, matching the shims in $TOOLS
# -FD: pin as/ld to those shims
# -Xr: emit a linker script (link.res) for the FPC driver
# shellcheck disable=SC2086
"$PPCROSS" funcmd.dpr -n -B -Sd -O2 -Xs -Tlinux -dLinux \
    -XPriscv64-linux- -Xr \
    -Fu"$UNITS" $FU_EXTRA -FD"$TOOLS" $LINK_FLAGS \
    -FU"$BUILD" -FE"$BUILD" $FEATURES $MT_FLAGS "$@"

FULL_SUFFIX=""
if [ "$FULL" = "1" ]; then
    FULL_SUFFIX="-musl"
fi
OUT="${FUN_RISCV_OUT:-$HERE/../../../fun/funcmd-linux-riscv64${FULL_SUFFIX}${MT_SUFFIX}${FUN_SAFE_LEVEL:+-safe}}"
cp -f "$BUILD/funcmd" "$OUT"
echo "Copied funcmd to $OUT"
