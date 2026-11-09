#!/bin/sh
# ============================================================
# make-linux-loongarch64.sh -- cross-build funcmd.dpr for Linux LoongArch64
# from an x86_64 Linux host. Counterpart of make-linux-aarch64.sh.
#
# The LoongArch64 FPC target is not in a stable release yet. Run
# bootstrap-linux-loongarch64.sh first; it produces the cross compiler, the
# RTL/rtl-objpas/hash units and the GNU binutils shims used here.
#
# Current capability boundary (same as the aarch64 cross artifact):
#   - core interpreter + portable standard library: yes
#   - regex: no. The bundled PCRE is C and needs a target libc; the aarch64
#     cross build has the same limitation.
#   - FFI (getapi): no. Needs a loongarch64 libffi.
#   - TinyCC / #!c: no. TinyCC has no LoongArch backend.
#   - lib-asm / #!asm: no. Only the x86 and aarch64 encoders exist.
# The build is still useful for running the language, demos and the portable
# stdlib under qemu or on real LoongArch hardware.
#
# Usage:
#   ./make-linux-loongarch64.sh
#   LOONG_FPC_ROOT=/opt/loong ./make-linux-loongarch64.sh
#   ./make-linux-loongarch64.sh -dFunTraceback ...   # extra FPC switches
#
# Needs: bootstrap-linux-loongarch64.sh run first (or LOONG_FPC_ROOT pointing
# at its output).
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

ROOT="${LOONG_FPC_ROOT:-$HOME/.fun/linux-loongarch64}"
PPCROSS="${LOONG_PPCROSS:-$ROOT/bin/ppcrossloongarch64}"
FULL="${FULL:-0}"
SYSROOT="${LOONG_SYSROOT:-}"

if [ "$FULL" = "1" ]; then
    UNITS="${LOONG_UNITS:-$ROOT/units-libc/loongarch64-linux}"
    UNITS_OBJPAS="${LOONG_UNITS_OBJPAS:-$ROOT/units-objpas-libc/loongarch64-linux}"
    UNITS_HASH="${LOONG_UNITS_HASH:-$ROOT/units-hash-libc/loongarch64-linux}"
    UNITS_FFI="${LOONG_UNITS_FFI:-$ROOT/units-ffi/loongarch64-linux}"
else
    UNITS="${LOONG_UNITS:-$ROOT/units/loongarch64-linux}"
    UNITS_OBJPAS="${LOONG_UNITS_OBJPAS:-$ROOT/units-objpas/loongarch64-linux}"
    UNITS_HASH="${LOONG_UNITS_HASH:-$ROOT/units-hash/loongarch64-linux}"
    UNITS_FFI=""
fi
TOOLS="${LOONG_TOOLS:-$ROOT/tools}"

[ -x "$PPCROSS" ]  || { echo "ppcrossloongarch64 not found: $PPCROSS" >&2
                        echo "Run bootstrap-linux-loongarch64.sh first." >&2; exit 1; }
[ -f "$UNITS/system.ppu" ] || { echo "loongarch64-linux units not found: $UNITS" >&2
                                echo "Run bootstrap-linux-loongarch64.sh first." >&2; exit 1; }
[ -x "$TOOLS/loongarch64-linux-as" ] || { echo "assembler not found under $TOOLS" >&2; exit 1; }
[ -x "$TOOLS/loongarch64-linux-ld" ] || { echo "linker not found under $TOOLS" >&2; exit 1; }

LINK_FLAGS=""
if [ "$FULL" = "1" ]; then
    [ -n "$SYSROOT" ] || { echo "FULL=1 needs LOONG_SYSROOT (see prepare-linux-loongarch64-sysroot.sh)" >&2; exit 1; }
    [ -f "$UNITS_FFI/ffi.ppu" ] || { echo "libffi binding not found: $UNITS_FFI/ffi.ppu" >&2
                                     echo "Run bootstrap-linux-loongarch64.sh with FPC_USE_LIBC=1." >&2; exit 1; }
    [ -f "$SYSROOT/lib/ld-musl-loongarch64.so.1" ] || { echo "musl sysroot not found: $SYSROOT" >&2; exit 1; }
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
if [ "$FULL" = "1" ]; then
    FU_EXTRA="$FU_EXTRA -Fu$HERE/../../lib"
fi

# -dFunNoRes: the cross toolchain has no loongarch64 fpcres, so skip the
# Windows version resource. It is not used on Linux.
FEATURES="$FEATURES -dFunNoRes"

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/fun-lin-loong-build-XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
echo "Building funcmd for linux/loongarch64 with $PPCROSS"
# -n: ignore the host fpc.cfg
# -XP: FPC's cross prefix, matching the shims in $TOOLS
# -FD: pin as/ld to those shims
# -Xr: emit a linker script (link.res) for the FPC driver
# shellcheck disable=SC2086
"$PPCROSS" funcmd.dpr -n -B -Sd -O2 -Xs -Tlinux -dLinux \
    -XPloongarch64-linux- -Xr \
    -Fu"$UNITS" $FU_EXTRA -FD"$TOOLS" $LINK_FLAGS \
    -FU"$BUILD" -FE"$BUILD" $FEATURES "$@"

FULL_SUFFIX=""
if [ "$FULL" = "1" ]; then
    FULL_SUFFIX="-musl"
fi
OUT="${FUN_LOONG_OUT:-$HERE/../../../fun/funcmd-linux-loongarch64${FULL_SUFFIX}${FUN_SAFE_LEVEL:+-safe}}"
cp -f "$BUILD/funcmd" "$OUT"
echo "Copied funcmd to $OUT"
