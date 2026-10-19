#!/bin/sh
# ============================================================
# make-linux-aarch64.sh -- cross-build funcmd.dpr for Linux aarch64 (arm64)
# from a Linux x86_64 host. Counterpart of make-linux-x86_64.sh.
#
# Assembly and linking are done by src/prj/fun/linux-aarch64/{as,ld} (Zig's
# clang/lld) against the aarch64-linux FPC units built by
# bootstrap-linux-aarch64.sh, so no aarch64 binutils or glibc is needed. The
# result is a static, syscall-based ELF.
#
# Not enabled yet (they need libraries that are not cross-built):
#   - Regex  (-dRegex, vendored PCRE): needs a libc, so it is not linked into
#     the -nostdlib static binary.
#   - getapi  (-dLinuxFFI, libffi): needs libffi for aarch64-linux.
# So this artifact is the core interpreter (language + pure stdlib); it is
# mainly for running lib-asm-a64's encoder tests under qemu/arm hosts once
# those two pieces are added. The binary is kept in fun/ (git-ignored).
#
# Usage:
#   ./make-linux-aarch64.sh
#   A64_FPC_ROOT=/opt/a64 ./make-linux-aarch64.sh
#   ./make-linux-aarch64.sh -dFunTraceback ...   # extra FPC switches appended
#
# Needs: bootstrap-linux-aarch64.sh run first (or A64_FPC_ROOT pointing at it).
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

ROOT="${A64_FPC_ROOT:-$HOME/.fun/linux-aarch64}"
ZIG="${ZIG:-${DARWIN_FPC_ROOT:-$HOME/.fun/darwin-cross}/zig/zig}"
PPCROSS="${PPCROSS:-${DARWIN_FPC_ROOT:-$HOME/.fun/darwin-cross}/bin/ppcrossa64}"
UNITS="${A64_UNITS:-$ROOT/units/aarch64-linux}"
UNITS_OBJPAS="${A64_UNITS_OBJPAS:-$ROOT/units-objpas/aarch64-linux}"
UNITS_HASH="${A64_UNITS_HASH:-$ROOT/units-hash/aarch64-linux}"

[ -x "$PPCROSS" ]  || { echo "ppcrossa64 not found: $PPCROSS (set PPCROSS=...)" >&2; exit 1; }
[ -f "$UNITS/system.ppu" ] || { echo "aarch64-linux units not found: $UNITS" >&2
                                echo "Run bootstrap-linux-aarch64.sh first." >&2; exit 1; }
[ -x "$ZIG" ]      || { echo "zig not found: $ZIG (set ZIG=...)" >&2; exit 1; }

# --- private tools dir: FPC looks for <cpu>-<os>-as / -ld / -fpcres --------
TOOLS="$(mktemp -d "${TMPDIR:-/tmp}/fun-lin-a64-tools-XXXXXX")"
trap 'rm -rf "$TOOLS"' EXIT
for t in as ld; do
  cp -f "$HERE/linux-aarch64/$t" "$TOOLS/$t"; chmod +x "$TOOLS/$t"
  ln -sf "$t" "$TOOLS/aarch64-linux-$t"
done
if command -v fpcres >/dev/null 2>&1; then
  ln -sf "$(command -v fpcres)" "$TOOLS/aarch64-linux-fpcres"
elif [ -x "$HOME/fpc-3.2.2/bin/fpcres" ]; then
  ln -sf "$HOME/fpc-3.2.2/bin/fpcres" "$TOOLS/aarch64-linux-fpcres"
fi
PATH="$TOOLS:$PATH"
export PATH ZIG

# --- optional -dMD5 when the hash units are present -----------------------
FU_EXTRA=""
if [ "${FUNPACK:-}" = "user" ]; then
  FEATURES="-dFunPackUser"
else
  FEATURES="-dFunPack"
fi
if [ -f "$UNITS_HASH/md5.ppu" ] && [ -f "$UNITS_HASH/sha1.ppu" ]; then
  FEATURES="$FEATURES -dMD5"
  FU_EXTRA="$FU_EXTRA -Fu$UNITS_HASH"
  echo "MD5/SHA1 enabled."
else
  echo "md5/sha1 units not found - building without -dMD5." >&2
fi
[ -d "$UNITS_OBJPAS" ] && FU_EXTRA="$FU_EXTRA -Fu$UNITS_OBJPAS"

# --- build ----------------------------------------------------------------
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/fun-lin-a64-build-XXXXXX")"
echo "Building funcmd for linux/aarch64 with $PPCROSS"
# -n: ignore the host fpc.cfg (its unit paths are for the build host)
# -XP: FPC's cross-prefix, so it looks for aarch64-linux-{as,ld,fpcres}
# -FD: pin those to our shims
# shellcheck disable=SC2086
"$PPCROSS" funcmd.dpr -n -B -Sd -O2 -Tlinux -dLinux -XPaarch64-linux- -Xr \
    -Fu"$UNITS" $FU_EXTRA -FD"$TOOLS" \
    -FU"$BUILD" -FE"$BUILD" $FEATURES "$@"

OUT="${FUN_A64_OUT:-$HERE/../../../fun/funcmd-linux-aarch64}"
cp -f "$BUILD/funcmd" "$OUT"
echo "Copied funcmd to $OUT"
rm -rf "$BUILD"
