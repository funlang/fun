#!/bin/sh
# ============================================================
# bootstrap-linux-aarch64.sh -- build the Free Pascal aarch64-linux cross units
# needed by make-linux-aarch64.sh, on a Linux x86_64 host.
#
# It produces the aarch64-linux RTL plus the rtl-objpas / hash units the
# interpreter uses (variants, dateutils, strutils; md5, sha1). Assembly and
# linking go through src/prj/fun/linux-aarch64/{as,ld}, which hand the work to
# the clang/lld bundled with Zig, so no aarch64 binutils and no glibc are
# required (the aarch64-linux FPC RTL is syscall-based).
#
# It reuses the ppcrossa64 from the darwin cross toolchain
# (bootstrap-darwin-cross.sh); a compiler binary is CPU-specific but can target
# any OS it has units for.
#
# Result:
#   $A64_FPC_ROOT/            (default ~/.fun/linux-aarch64)
#     units/aarch64-linux/           RTL
#     units-objpas/aarch64-linux/    variants, dateutils, strutils
#     units-hash/aarch64-linux/      md5, sha1
#
# Usage:
#   ./bootstrap-linux-aarch64.sh
#   A64_FPC_ROOT=/opt/a64 PPCROSS=/path/ppcrossa64 FPC_SRC=/data/fpc ./bootstrap-linux-aarch64.sh
#
# Needs: an FPC 3.2.x source tree (FPC_SRC), ppcrossa64, Zig 0.13, make.
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

ROOT="${A64_FPC_ROOT:-$HOME/.fun/linux-aarch64}"
FPC_SRC="${FPC_SRC:-${DARWIN_FPC_SRC:-$HOME/.fun/darwin-cross-build/source-release_3_2_2}}"
ZIG="${ZIG:-${DARWIN_FPC_ROOT:-$HOME/.fun/darwin-cross}/zig/zig}"
# ppcrossa64 lives in the darwin toolchain by default; a compiler binary is
# CPU-specific, so the same one drives the linux target once its units exist.
PPCROSS="${PPCROSS:-${DARWIN_FPC_ROOT:-$HOME/.fun/darwin-cross}/bin/ppcrossa64}"

[ -x "$PPCROSS" ]  || { echo "ppcrossa64 not found: $PPCROSS (set PPCROSS=...)" >&2; exit 1; }
[ -f "$FPC_SRC/rtl/Makefile" ] || { echo "FPC source not found: $FPC_SRC (set FPC_SRC=...)" >&2; exit 1; }
[ -x "$ZIG" ]      || { echo "zig not found: $ZIG (set ZIG=...)" >&2; exit 1; }

CPU=aarch64
export ZIG
mkdir -p "$ROOT/bin" "$ROOT/units/$CPU-linux" "$ROOT/units-objpas/$CPU-linux" "$ROOT/units-hash/$CPU-linux"

# --- private tools dir: FPC looks for <cpu>-<os>-as / -ld / -fpcres --------
TOOLS="$(mktemp -d "${TMPDIR:-/tmp}/fun-lin-a64-tools-XXXXXX")"
trap 'rm -rf "$TOOLS"' EXIT
for t in as ld; do
  cp -f "$HERE/linux-aarch64/$t" "$TOOLS/$t"; chmod +x "$TOOLS/$t"
  ln -sf "$t" "$TOOLS/$CPU-linux-$t"
done
if command -v fpcres >/dev/null 2>&1; then
  ln -sf "$(command -v fpcres)" "$TOOLS/$CPU-linux-fpcres"
elif [ -x "$HOME/fpc-3.2.2/bin/fpcres" ]; then
  ln -sf "$HOME/fpc-3.2.2/bin/fpcres" "$TOOLS/$CPU-linux-fpcres"
fi
PATH="$TOOLS:$PATH"
export PATH

# --- 1. RTL ---------------------------------------------------------------
echo "=== building $CPU-linux RTL"
make -C "$FPC_SRC/rtl" "CPU_TARGET=$CPU" OS_TARGET=linux FPC="$PPCROSS"
cp -f "$FPC_SRC/rtl/units/$CPU-linux/"*.ppu "$FPC_SRC/rtl/units/$CPU-linux/"*.o \
      "$ROOT/units/$CPU-linux/"

# --- 2. rtl-objpas units the interpreter needs ----------------------------
echo "=== building rtl-objpas units"
TMPO="$(mktemp -d)"; mkdir -p "$TMPO"
for u in variants dateutils strutils; do
  ( cd "$FPC_SRC/packages/rtl-objpas/src/inc" && \
      "$PPCROSS" "$u.pp" -n -B -Tlinux -XP"$CPU-linux-" -Xr \
        -Fu"$ROOT/units/$CPU-linux" \
        -Fu"$FPC_SRC/packages/rtl-objpas/src/inc" \
        -Fu"$FPC_SRC/packages/rtl-objpas/src/common" \
        -FU"$TMPO" -FE"$TMPO" >/dev/null ) \
    || echo "warning: could not build $u" >&2
done
cp -f "$TMPO"/*.ppu "$TMPO"/*.o "$ROOT/units-objpas/$CPU-linux/" 2>/dev/null || true

# --- 3. md5 / sha1 (for -dMD5) --------------------------------------------
echo "=== building hash units"
TMPH="$(mktemp -d)"; mkdir -p "$TMPH"
for u in md5 sha1; do
  ( cd "$FPC_SRC/packages/hash/src" && \
      "$PPCROSS" "$u.pp" -n -B -Tlinux -XP"$CPU-linux-" -Xr \
        -Fu"$ROOT/units/$CPU-linux" -FU"$TMPH" -FE"$TMPH" >/dev/null ) \
    || echo "warning: could not build $u" >&2
done
cp -f "$TMPH"/*.ppu "$TMPH"/*.o "$ROOT/units-hash/$CPU-linux/" 2>/dev/null || true

echo
echo "Cross units ready under: $ROOT"
echo "Build the interpreter with:"
echo "  A64_FPC_ROOT=$ROOT PPCROSS=$PPCROSS $HERE/make-linux-aarch64.sh"
