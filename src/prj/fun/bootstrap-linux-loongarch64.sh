#!/bin/sh
# ============================================================
# bootstrap-linux-loongarch64.sh -- build the Free Pascal
# loongarch64-linux cross compiler and units on an x86_64 Linux host.
#
# FPC has no LoongArch64 target in a stable release yet (3.2.4 still lacks it;
# the port lives on main/3.3.1). This script therefore bootstraps both the
# native and the cross compiler from an FPC source tree, then builds the RTL
# plus the rtl-objpas and hash units the interpreter needs.
#
# GNU binutils for loongarch64 is required. On Debian/Ubuntu install
# binutils-loongarch64-linux-gnu; otherwise point CROSSBINDIR at a directory
# containing loongarch64-linux-{as,ld,ar,ranlib} or the -gnu- prefixed forms.
#
# Usage:
#   FPC_BOOT=/path/to/fpc-3.2.2/bin/ppcx64 \
#   FPC_SRC=/path/to/fpc-3.3.1/source \
#   CROSSBINDIR=/usr/bin \
#   ./bootstrap-linux-loongarch64.sh
#
# Output ($LOONG_FPC_ROOT, default ~/.fun/linux-loongarch64):
#   bin/ppcrossloongarch64
#   units/loongarch64-linux/          RTL
#   units-objpas/loongarch64-linux/   variants, dateutils, strutils
#   units-hash/loongarch64-linux/     md5, sha1
#   tools/loongarch64-linux-{as,ld,ar,ranlib}
#
# Then build the interpreter with:
#   ./make-linux-loongarch64.sh
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

ROOT="${LOONG_FPC_ROOT:-$HOME/.fun/linux-loongarch64}"
JOBS="${JOBS:-2}"
FPC_USE_LIBC="${FPC_USE_LIBC:-0}"
CPU=loongarch64

FPC_BOOT="${FPC_BOOT:-}"
FPC_SRC="${FPC_SRC:-}"
CROSSBINDIR="${CROSSBINDIR:-}"

[ -n "$FPC_BOOT" ] || { echo "bootstrap: set FPC_BOOT to an FPC 3.2.x ppcx64" >&2; exit 1; }
[ -x "$FPC_BOOT" ] || { echo "bootstrap: FPC_BOOT is not executable: $FPC_BOOT" >&2; exit 1; }
[ -n "$FPC_SRC" ] || { echo "bootstrap: set FPC_SRC to an FPC main/3.3.x source tree" >&2; exit 1; }
[ -f "$FPC_SRC/compiler/pp.pas" ] || { echo "bootstrap: not an FPC source tree: $FPC_SRC" >&2; exit 1; }

find_tool() {
    name="$1"
    for cand in "$CROSSBINDIR/${CPU}-linux-${name}" \
                "$CROSSBINDIR/${CPU}-linux-gnu-${name}" \
                "$(command -v "${CPU}-linux-${name}" 2>/dev/null || true)" \
                "$(command -v "${CPU}-linux-gnu-${name}" 2>/dev/null || true)"; do
        [ -n "$cand" ] && [ -x "$cand" ] && { printf '%s\n' "$cand"; return 0; }
    done
    return 1
}

AS_BIN="$(find_tool as)" || { echo "bootstrap: loongarch64 assembler not found (set CROSSBINDIR)" >&2; exit 1; }
LD_BIN="$(find_tool ld)" || { echo "bootstrap: loongarch64 linker not found (set CROSSBINDIR)" >&2; exit 1; }
AR_BIN="$(find_tool ar 2>/dev/null || command -v ar)" || true
RANLIB_BIN="$(find_tool ranlib 2>/dev/null || command -v ranlib)" || true

mkdir -p "$ROOT/bin" "$ROOT/units/$CPU-linux" "$ROOT/units-objpas/$CPU-linux" \
         "$ROOT/units-hash/$CPU-linux" "$ROOT/tools"
if [ "$FPC_USE_LIBC" = "1" ]; then
    mkdir -p "$ROOT/units-libc/$CPU-linux" "$ROOT/units-objpas-libc/$CPU-linux" \
             "$ROOT/units-hash-libc/$CPU-linux" "$ROOT/units-ffi/$CPU-linux"
fi

# Private binutils names for FPC: <cpu>-<os>-as / -ld.
for pair in "as:$AS_BIN" "ld:$LD_BIN" "ar:$AR_BIN" "ranlib:$RANLIB_BIN"; do
    name=${pair%%:*}; path=${pair#*:}
    [ -n "$path" ] || continue
    ln -sf "$path" "$ROOT/tools/${CPU}-linux-${name}"
done
TOOLS="$ROOT/tools"
export PATH="$TOOLS:$PATH"

echo "=== bootstrap native compiler and RTL"
( cd "$FPC_SRC" && make -C compiler cycle \
    FPC="$FPC_BOOT" PP="$FPC_BOOT" -j"$JOBS" )

echo "=== bootstrap $CPU-linux cross compiler and RTL"
( cd "$FPC_SRC" && make -C compiler cycle CROSSINSTALL=1 \
    CPU_TARGET="$CPU" OS_TARGET=linux \
    CROSSBINDIR="$TOOLS" BINUTILSPREFIX="${CPU}-linux-" \
    FPC="$FPC_SRC/compiler/ppcx64" PP="$FPC_SRC/compiler/ppcx64" -j"$JOBS" )

PPCROSS="$FPC_SRC/compiler/ppcross${CPU}"
[ -x "$PPCROSS" ] || { echo "bootstrap: $PPCROSS was not produced" >&2; exit 1; }
cp -f "$PPCROSS" "$ROOT/bin/ppcross${CPU}"

echo "=== install RTL units"
cp -f "$FPC_SRC/rtl/units/${CPU}-linux/"*.ppu \
      "$FPC_SRC/rtl/units/${CPU}-linux/"*.o \
      "$ROOT/units/${CPU}-linux/"

build_units() {
    src="$1"; out="$2"; shift 2
    for u in "$@"; do
        ( cd "$src" && "$ROOT/bin/ppcross${CPU}" "$u" -n -B -Tlinux \
            -XP"${CPU}-linux-" -FD"$TOOLS" \
            -Fu"$ROOT/units/${CPU}-linux" -Fu"$FPC_SRC/packages/rtl-objpas/src/inc" \
            -Fu"$FPC_SRC/packages/rtl-objpas/src/common" \
            -FU"$out" -FE"$out" )
    done
}

echo "=== install rtl-objpas units"
build_units "$FPC_SRC/packages/rtl-objpas/src/inc" "$ROOT/units-objpas/$CPU-linux" \
    variants.pp dateutils.pp strutils.pp

echo "=== install hash units"
( cd "$FPC_SRC/packages/hash/src" && \
  for u in md5 sha1; do
      "$ROOT/bin/ppcross${CPU}" "$u.pp" -n -B -Tlinux \
          -XP"${CPU}-linux-" -FD"$TOOLS" \
          -Fu"$ROOT/units/${CPU}-linux" \
          -FU"$ROOT/units-hash/$CPU-linux" -FE"$ROOT/units-hash/$CPU-linux"
  done )

if [ "$FPC_USE_LIBC" = "1" ]; then
    echo "=== rebuild RTL with libc startup"
    ( cd "$FPC_SRC" && make -C compiler cycle CROSSINSTALL=1 \
        CPU_TARGET="$CPU" OS_TARGET=linux \
        CROSSBINDIR="$TOOLS" BINUTILSPREFIX="${CPU}-linux-" \
        FPC="$FPC_SRC/compiler/ppcx64" PP="$FPC_SRC/compiler/ppcx64" \
        RTLOPT="-dFPC_USE_LIBC" -j"$JOBS" )
    cp -f "$FPC_SRC/rtl/units/${CPU}-linux/"*.ppu \
          "$FPC_SRC/rtl/units/${CPU}-linux/"*.o \
          "$ROOT/units-libc/${CPU}-linux/"

    build_units_libc() {
        src="$1"; out="$2"; shift 2
        for u in "$@"; do
            ( cd "$src" && "$ROOT/bin/ppcross${CPU}" "$u" -n -B -Tlinux \
                -dFPC_USE_LIBC -XP"${CPU}-linux-" -FD"$TOOLS" \
                -Fu"$ROOT/units-libc/${CPU}-linux" \
                -Fu"$FPC_SRC/packages/rtl-objpas/src/inc" \
                -Fu"$FPC_SRC/packages/rtl-objpas/src/common" \
                -FU"$out" -FE"$out" )
        done
    }

    echo "=== install rtl-objpas units (libc)"
    build_units_libc "$FPC_SRC/packages/rtl-objpas/src/inc" \
        "$ROOT/units-objpas-libc/$CPU-linux" \
        variants.pp dateutils.pp strutils.pp

    echo "=== install hash units (libc)"
    ( cd "$FPC_SRC/packages/hash/src" && \
      for u in md5 sha1; do
          "$ROOT/bin/ppcross${CPU}" "$u.pp" -n -B -Tlinux \
              -dFPC_USE_LIBC -XP"${CPU}-linux-" -FD"$TOOLS" \
              -Fu"$ROOT/units-libc/${CPU}-linux" \
              -FU"$ROOT/units-hash-libc/$CPU-linux" \
              -FE"$ROOT/units-hash-libc/$CPU-linux"
      done )

    echo "=== install libffi binding (libc)"
    ( cd "$FPC_SRC/packages/libffi/src" && \
      "$ROOT/bin/ppcross${CPU}" ffi.pp -Mobjfpc -n -B -Tlinux \
          -dFPC_USE_LIBC -XP"${CPU}-linux-" -FD"$TOOLS" \
          -Fu"$ROOT/units-libc/${CPU}-linux" \
          -FU"$ROOT/units-ffi/$CPU-linux" -FE"$ROOT/units-ffi/$CPU-linux" )
fi

echo
echo "LoongArch64 cross FPC ready under: $ROOT"
echo "Build the interpreter with:"
if [ "$FPC_USE_LIBC" = "1" ]; then
    echo "  FULL=1 LOONG_SYSROOT=<musl-sysroot> LOONG_FPC_ROOT=$ROOT $HERE/make-linux-loongarch64.sh"
else
    echo "  LOONG_FPC_ROOT=$ROOT $HERE/make-linux-loongarch64.sh"
fi
