#!/bin/sh
# ============================================================
# make-win-arm64.sh -- cross-build funcmd.dpr for Windows on arm64
# (win64/aarch64) from a Linux x86_64 host.
#
# FPC 3.2.2 has no win64/aarch64 target. This script uses an FPC 3.3.1
# cross toolchain built from source (see .github/workflows/winarm64.yml):
#
#   make all OS_TARGET=win64 CPU_TARGET=aarch64 PP=ppcx64
#   make crossinstall OS_TARGET=win64 CPU_TARGET=aarch64 \
#        PP=ppcx64 INSTALL_PREFIX=~/.fun/win-arm64
#
# The aarch64-win64 backend assembles through clang, so the script puts
# src/prj/fun/win-arm64/clang (a Zig-driver shim) on PATH as both `clang`
# and `aarch64-win64-clang`.
#
# Optional DLLs work exactly as on win-x64: pcre3.dll enables regex
# (-dRegex -dPCRE_WinDLL) and ffi.dll enables getapi (-dWinFFI). Both must be
# arm64 builds; they are looked up in this directory.
#
# Usage:
#   ./make-win-arm64.sh
#   WINARM_FPC_ROOT=~/.fun/win-arm64 ZIG=~/zig/zig ./make-win-arm64.sh
#   SAFE=strict ./make-win-arm64.sh
#   FUN_WINARM_OUT=$PWD/fun/funcmd-win-arm64.exe ./make-win-arm64.sh
#
# Output: funcmd.exe (funcmd-safe.exe under SAFE=...) in this directory,
# unless FUN_WINARM_OUT overrides it.
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

ROOT="${WINARM_FPC_ROOT:-$HOME/.fun/win-arm64}"
PPCROSS="${PPCROSS:-$ROOT/lib/fpc/3.3.1/ppcrossa64}"
UNITS="${WINARM_UNITS:-$ROOT/lib/fpc/3.3.1/units/aarch64-win64}"
ZIG="${ZIG:-$HOME/.fun/zig/zig}"

[ -x "$PPCROSS" ]      || { echo "ppcrossa64 not found: $PPCROSS (set WINARM_FPC_ROOT/PPCROSS)" >&2; exit 1; }
[ -f "$UNITS/rtl/system.ppu" ] || { echo "aarch64-win64 units not found: $UNITS" >&2; exit 1; }
[ -x "$ZIG" ]          || { echo "zig not found: $ZIG (set ZIG)" >&2; exit 1; }

# SAFE=... builds a capability-restricted variant with the same macros as the
# other targets.
. "$HERE/safe-flags.sh"
fun_safe_parse || exit 2

# Private tools dir: FPC looks for aarch64-win64-clang when it assembles.
TOOLS="$(mktemp -d "${TMPDIR:-/tmp}/fun-win-a64-tools-XXXXXX")"
trap 'rm -rf "$TOOLS"' EXIT
cp -f "$HERE/win-arm64/clang" "$TOOLS/clang"
chmod +x "$TOOLS/clang"
ln -sf clang "$TOOLS/aarch64-win64-clang"
PATH="$TOOLS:$PATH"
export PATH ZIG

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/fun-win-a64-build-XXXXXX")"
OUT="${FUN_WINARM_OUT:-$HERE/funcmd${FUN_SAFE_LEVEL:+-safe}.exe}"

FEATURES="-dFunPack -dMD5 -dFunTraceback $FUN_SAFE_FLAGS"
[ -f pcre3.dll ] && FEATURES="$FEATURES -dRegex -dPCRE_WinDLL"
[ -f ffi.dll ]   && FEATURES="$FEATURES -dWinFFI"

echo "Building funcmd for win64/aarch64 with $PPCROSS"
# -n: ignore the build host's fpc.cfg (its units are for Linux).
# -Fu<units>/* covers the snapshot's package directories, as fpc.cfg does.
# shellcheck disable=SC2086
"$PPCROSS" funcmd.dpr -n -B -Sd -O2 -Twin64 -Paarch64 -dWin64 \
    -XPaarch64-win64- \
    -Fu..\\..\\lib -Fu"$UNITS/*" -Fu"$UNITS/rtl" \
    -FU"$BUILD" -FE"$BUILD" -o"$OUT" \
    $FEATURES

[ -f "$OUT" ] || { echo "build produced no $OUT" >&2; exit 1; }
echo "Copied funcmd to $OUT"
rm -rf "$BUILD"
