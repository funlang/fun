#!/bin/sh
# ============================================================
# bootstrap-darwin-cross.sh -- build the Free Pascal macOS cross toolchain
# needed by make-darwin.sh, entirely on a Linux host.
#
# It does three things:
#   1. builds FPC cross compilers (ppcrossx64 / ppcrossa64) plus the Darwin RTL
#      for x86_64-darwin and aarch64-darwin from the FPC 3.2.2 source;
#   2. downloads Zig and uses it as the Mach-O assembler/linker (no Apple SDK
#      needed);
#   3. cross-builds the vendored PCRE 8 into libpcre.a for both architectures.
#
# The result is a self-contained toolchain tree:
#
#   $DARWIN_FPC_ROOT/           (default ~/.fun/darwin-cross)
#     bin/ppcrossx64  bin/ppcrossa64
#     units/{x86_64,aarch64}-darwin/        RTL
#     units-objpas/{...}/                   variants, dateutils
#     units-hash/{...}/                     md5, sha1
#     units-libffi/{...}/                   ffi (optional; needs DARWIN_SDK stub)
#     libffi/libffi.tbd                     libffi linker stub (from DARWIN_SDK)
#     pcre/{x86_64,aarch64}-darwin/libpcre.a
#     zig/zig
#
# Usage:
#   ./bootstrap-darwin-cross.sh
#   DARWIN_FPC_ROOT=/opt/darwin WORK=/data/fpc-cross JOBS=4 ./bootstrap-darwin-cross.sh
#   FPC=/path/to/ppcx64 ./bootstrap-darwin-cross.sh
#
# Needs: a host FPC 3.2.x (FPC=/path/to/ppcx64 or `fpc` on PATH), make, curl or
# wget, tar, and ~2 GB of free space.
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

ROOT="${DARWIN_FPC_ROOT:-$HOME/.fun/darwin-cross}"
WORK="${WORK:-$HOME/.fun/darwin-cross-build}"
# Optional: path to a MacOSX*.sdk (or just its usr/lib). Only used to seed the
# libffi linker stubs (usr/lib/libffi.tbd + libffi-trampolines.tbd) so that
# -dDarwinFFI (Fun getapi on macOS) can link. Zig ships libSystem only.
DARWIN_SDK="${DARWIN_SDK:-}"
JOBS="${JOBS:-2}"
FPC_TAG="${FPC_TAG:-release_3_2_2}"
FPC_VER="3.2.2"
FPC_SRC_URL="https://gitlab.com/freepascal.org/fpc/source/-/archive/$FPC_TAG/source-$FPC_TAG.tar.gz"
ZIG_VER="${ZIG_VER:-0.13.0}"
# Zig 0.13 keeps the Mach-O assembler/linker and libSystem stub we need and runs
# on older glibc/kernels (0.14 panicked on CentOS 7). The archive name differs
# in 0.14+; this pins the 0.13 layout.
ZIG_DIRNAME="zig-linux-x86_64-$ZIG_VER"
ZIG_URL="https://ziglang.org/download/$ZIG_VER/$ZIG_DIRNAME.tar.xz"
PCRE_SRC="${PCRE_SRC:-$HERE/../../3rd/pcre-8}"
CPUS="${CPUS:-x86_64 aarch64}"

# --- locate the host FPC driver ---------------------------------------------
if [ -n "$FPC" ]; then
  FPC_BIN="$FPC"
elif command -v fpc >/dev/null 2>&1; then
  FPC_BIN="$(command -v fpc)"
elif [ -x "$HOME/fpc-3.2.2/bin/fpc" ]; then
  FPC_BIN="$HOME/fpc-3.2.2/bin/fpc"
else
  echo "Host Free Pascal not found. Set FPC=<path-to-fpc>." >&2
  exit 1
fi
# the make build wants the ppcx64 driver binary
PPCX64="$(dirname "$FPC_BIN")/ppcx64"
[ -x "$PPCX64" ] || PPCX64="$FPC_BIN"
echo "Host FPC: $FPC_BIN"

fetch() {
  url="$1"; out="$2"
  [ -f "$out" ] && return 0
  echo "Downloading $url"
  if command -v curl >/dev/null 2>&1; then curl -fL -A Mozilla/5.0 -o "$out" "$url"
  else wget -O "$out" "$url"; fi
}

mkdir -p "$WORK" "$ROOT/bin"

# --- 1. FPC source ----------------------------------------------------------
FPCSRC="$WORK/source-$FPC_TAG"
if [ ! -d "$FPCSRC" ]; then
  fetch "$FPC_SRC_URL" "$WORK/fpc-$FPC_VER-src.tar.gz"
  tar xf "$WORK/fpc-$FPC_VER-src.tar.gz" -C "$WORK"
fi

# --- 2. Zig -----------------------------------------------------------------
ZIGDIR="$WORK/$ZIG_DIRNAME"
if [ ! -x "$ZIGDIR/zig" ]; then
  fetch "$ZIG_URL" "$WORK/zig.tar.xz"
  tar xf "$WORK/zig.tar.xz" -C "$WORK"
fi
ZIG="$ZIGDIR/zig"
"$ZIG" version
export ZIG

# assembler shim dir for the RTL build (needs <cpu>-darwin-clang on PATH)
ASMTOOLS="$WORK/asmtools"
mkdir -p "$ASMTOOLS"
cp -f "$HERE/darwin/clang" "$ASMTOOLS/clang"; chmod +x "$ASMTOOLS/clang"

# --- 3. cross compilers + RTL ----------------------------------------------
for cpu in $CPUS; do
  case "$cpu" in
    x86_64)  ppc=ppcrossx64 ;;
    aarch64) ppc=ppcrossa64 ;;
    *) echo "unsupported CPU $cpu" >&2; exit 1 ;;
  esac
  ln -sf clang "$ASMTOOLS/$cpu-darwin-clang"
  echo "=== building $cpu-darwin cross compiler + RTL"
  ( cd "$FPCSRC" && PATH="$ASMTOOLS:$(dirname "$FPC_BIN"):$PATH" \
      make crossall CPU_TARGET="$cpu" OS_TARGET=darwin -j"$JOBS" NOGDB=1 \
        FPC="$PPCX64" ) \
    || echo "crossall reported errors for $cpu (expected: packages/rtti); continuing" >&2
  [ -x "$FPCSRC/compiler/$ppc" ] || { echo "missing $ppc" >&2; exit 1; }
  [ -f "$FPCSRC/rtl/units/$cpu-darwin/system.ppu" ] || { echo "missing $cpu-darwin RTL" >&2; exit 1; }

  # --- copy compiler + RTL into the install tree ---------------------------
  cp -f "$FPCSRC/compiler/$ppc" "$ROOT/bin/"
  mkdir -p "$ROOT/units/$cpu-darwin" "$ROOT/units-objpas/$cpu-darwin" "$ROOT/units-hash/$cpu-darwin"
  cp -f "$FPCSRC/rtl/units/$cpu-darwin/"*.ppu "$FPCSRC/rtl/units/$cpu-darwin/"*.o "$ROOT/units/$cpu-darwin/"

  # --- rtl-objpas units the interpreter needs (variants, dateutils, strutils) ---
  CROSS="$FPCSRC/compiler/$ppc"
  TMPO="$WORK/objpas-$cpu"; mkdir -p "$TMPO"
  for u in variants dateutils strutils; do
    ( cd "$FPCSRC/packages/rtl-objpas/src/inc" && PATH="$ASMTOOLS:$PATH" \
        "$CROSS" "$u.pp" -n -B -Tdarwin \
          -Fu"$FPCSRC/rtl/units/$cpu-darwin" \
          -Fu"$FPCSRC/packages/rtl-objpas/src/inc" \
          -Fu"$FPCSRC/packages/rtl-objpas/src/common" \
          -FU"$TMPO" -FE"$TMPO" >/dev/null ) \
      || echo "warning: could not build $u for $cpu" >&2
  done
  cp -f "$TMPO"/*.ppu "$TMPO"/*.o "$ROOT/units-objpas/$cpu-darwin/" 2>/dev/null || true

  # --- md5 / sha1 (for -dMD5) ---------------------------------------------
  TMPH="$WORK/hash-$cpu"; mkdir -p "$TMPH"
  for u in md5 sha1; do
    ( cd "$FPCSRC/packages/hash/src" && PATH="$ASMTOOLS:$PATH" \
        "$CROSS" "$u.pp" -n -B -Tdarwin \
          -Fu"$FPCSRC/rtl/units/$cpu-darwin" \
          -FU"$TMPH" -FE"$TMPH" >/dev/null ) \
      || echo "warning: could not build $u for $cpu" >&2
  done
  cp -f "$TMPH"/*.ppu "$TMPH"/*.o "$ROOT/units-hash/$cpu-darwin/" 2>/dev/null || true

  # --- libffi unit (for -dDarwinFFI: Fun getapi on macOS) ------------------
  # FPC's ffi unit declares its externals as `external 'ffi'`, so linking the
  # interpreter needs -lffi. Zig only ships a libSystem stub, so the libffi
  # stubs are seeded from a MacOSX*.sdk when DARWIN_SDK points at one.
  TMPF="$WORK/libffi-$cpu"; mkdir -p "$TMPF"
  ( cd "$FPCSRC/packages/libffi/src" && PATH="$ASMTOOLS:$PATH" \
      "$CROSS" ffi.pp -n -B -Tdarwin \
        -Fu"$FPCSRC/rtl/units/$cpu-darwin" \
        -FU"$TMPF" -FE"$TMPF" >/dev/null ) \
    || echo "warning: could not build ffi for $cpu" >&2
  mkdir -p "$ROOT/units-libffi/$cpu-darwin"
  cp -f "$TMPF"/*.ppu "$TMPF"/*.o "$ROOT/units-libffi/$cpu-darwin/" 2>/dev/null || true

  if [ -n "$DARWIN_SDK" ]; then
    mkdir -p "$ROOT/libffi"
    for t in libffi.tbd libffi-trampolines.tbd; do
      src="$DARWIN_SDK/usr/lib/$t"
      [ -f "$src" ] || src="$DARWIN_SDK/$t"
      if [ -f "$src" ]; then
        cp -f "$src" "$ROOT/libffi/"
        echo "libffi stub: $t"
      fi
    done
  fi

  # --- PCRE 8 (for -dRegex) ------------------------------------------------
  if [ -f "$PCRE_SRC/pcre_compile.c" ]; then
    case "$cpu" in aarch64) zt=aarch64-macos ;; *) zt=x86_64-macos ;; esac
    POUT="$ROOT/pcre/$cpu-darwin"; mkdir -p "$POUT"
    echo "=== cross-building PCRE 8 for $cpu"
    for f in pcre_byte_order pcre_chartables pcre_compile pcre_config \
             pcre_default_tables pcre_dfa_exec pcre_exec pcre_fullinfo \
             pcre_get pcre_globals pcre_maketables pcre_newline \
             pcre_refcount pcre_study pcre_tables pcre_ucd \
             pcre_valid_utf8 pcre_version pcre_xclass pcre_string_utils; do
      "$ZIG" cc -target "$zt" -c -O2 -DHAVE_CONFIG_H -DSUPPORT_PCRE8 \
        -I"$PCRE_SRC" "$PCRE_SRC/$f.c" -o "$POUT/$f.o"
    done
    "$ZIG" ar rcs "$POUT/libpcre.a" "$POUT"/*.o
  else
    echo "PCRE source not found at $PCRE_SRC - regex will be disabled." >&2
  fi
done

# --- 4. zig into the install tree ------------------------------------------
# Symlinked, not copied: zig locates its own lib/ next to the real executable,
# so the symlink keeps it working without duplicating ~250 MB. This makes
# $WORK a runtime dependency of the toolchain tree.
mkdir -p "$ROOT/zig"
ln -sf "$ZIG" "$ROOT/zig/zig"

echo
echo "Toolchain ready under: $ROOT"
echo "Build the interpreter with:"
echo "  CPU=all DARWIN_FPC_ROOT=$ROOT $HERE/make-darwin.sh"
