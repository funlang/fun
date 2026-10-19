#!/bin/sh
# ============================================================
# Fun - macOS (Darwin) cross build of funcmd.dpr, from Linux.
#
# Counterpart of make-linux-x86_64.sh for the macOS target. It cross-compiles a
# native Mach-O interpreter with Free Pascal's darwin cross compiler and links
# it with the Mach-O linker bundled in Zig (see darwin/ld, darwin/clang). No
# macOS SDK or Apple tools are required: Zig ships a libSystem stub.
#
# This produces the interpreter binary only. The Fun-level libraries have not
# been ported yet: there is no lib-tcc.so / libffi / /proc backend for macOS, and
# the *-lnx.fun backends are Linux-specific (see art/notes/macos-port.md). The
# build is a first "does it compile and link for the target" milestone.
#
# Toolchain layout (see bootstrap-darwin-cross.sh, or point the env vars at an
# existing install):
#
#   $DARWIN_FPC_ROOT/
#     bin/ppcrossx64          bin/ppcrossa64        # FPC darwin cross compilers
#     units/x86_64-darwin/    units/aarch64-darwin/ # RTL
#     units-objpas/<cpu>-darwin/                    # variants, dateutils
#     units-hash/<cpu>-darwin/                      # md5, sha1      (optional)
#     units-libffi/<cpu>-darwin/                    # ffi            (optional)
#     libffi/libffi.tbd                             # libffi stub    (optional)
#     pcre/<cpu>-darwin/libpcre.a                   # regex          (optional)
#     zig/zig                                       # Mach-O assembler+linker
#
# Usage:
#   ./make-darwin.sh                     # aarch64 (Apple Silicon) by default
#   CPU=x86_64 ./make-darwin.sh          # Intel Mac
#   CPU=all ./make-darwin.sh             # both
#   DARWIN_FPC_ROOT=/opt/darwin ./make-darwin.sh
#   ./make-darwin.sh -dFunTraceback ...  # extra FPC switches are appended
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

CPU="${CPU:-aarch64}"
ROOT="${DARWIN_FPC_ROOT:-$HOME/.fun/darwin-cross}"
ZIG="${ZIG:-$ROOT/zig/zig}"

# --- Resolve the FPC darwin cross compiler and its unit trees ---------------
ppc_name() {
  case "$1" in
    x86_64)  echo ppcrossx64 ;;
    aarch64) echo ppcrossa64 ;;
    *) echo "unsupported CPU: $1 (use x86_64 or aarch64)" >&2; exit 1 ;;
  esac
}

build_cpu() {
  cpu="$1"; shift
  local PPCROSS UNITS UNITS_OBJPAS UNITS_HASH PCRE_LIB TOOLS FPCRES BUILD OUT
  PPCROSS="${PPCROSS:-$ROOT/bin/$(ppc_name "$cpu")}"
  UNITS="${DARWIN_UNITS:-$ROOT/units/$cpu-darwin}"
  UNITS_OBJPAS="${DARWIN_UNITS_OBJPAS:-$ROOT/units-objpas/$cpu-darwin}"
  UNITS_HASH="${DARWIN_UNITS_HASH:-$ROOT/units-hash/$cpu-darwin}"
  UNITS_FFI="${DARWIN_UNITS_FFI:-$ROOT/units-libffi/$cpu-darwin}"
  FFI_LIBDIR="${DARWIN_LIBFFI_DIR:-$ROOT/libffi}"
  PCRE_LIB="${PCRE_LIB:-$ROOT/pcre/$cpu-darwin}"

  [ -x "$PPCROSS" ] || { echo "FPC darwin cross compiler not found: $PPCROSS" >&2
                         echo "Run bootstrap-darwin-cross.sh or set DARWIN_FPC_ROOT/PPCROSS." >&2; exit 1; }
  [ -d "$UNITS" ]   || { echo "darwin RTL units not found: $UNITS" >&2; exit 1; }
  [ -x "$ZIG" ]     || { echo "zig not found: $ZIG (set ZIG=...)" >&2; exit 1; }

  # --- Private tools dir: FPC looks for <cpu>-<os>-clang / -ld / -fpcres ----
  TOOLS="$(mktemp -d "${TMPDIR:-/tmp}/fun-darwin-tools-XXXXXX")"
  trap 'rm -rf "$TOOLS"' EXIT
  for t in clang ld; do
    cp -f "$HERE/darwin/$t" "$TOOLS/$t"; chmod +x "$TOOLS/$t"
    ln -sf "$t" "$TOOLS/$cpu-darwin-$t"
  done
  FPCRES=""
  if command -v fpcres >/dev/null 2>&1; then
    FPCRES="$(command -v fpcres)"
  elif [ -n "${FPC:-}" ] && [ -x "${FPC%/*}/fpcres" ]; then
    FPCRES="${FPC%/*}/fpcres"
  elif [ -x "$HOME/fpc-3.2.2/bin/fpcres" ]; then
    FPCRES="$HOME/fpc-3.2.2/bin/fpcres"
  fi
  if [ -n "$FPCRES" ]; then
    ln -sf "$FPCRES" "$TOOLS/fpcres"
    ln -sf "$FPCRES" "$TOOLS/$cpu-darwin-fpcres"
  fi
  PATH="$TOOLS:$PATH"
  export PATH ZIG

  # --- Optional features ----------------------------------------------------
  if [ "${FUNPACK:-}" = "user" ]; then
    FEATURES="-dFunPackUser"
  else
    FEATURES="-dFunPack"
  fi
  FU_EXTRA=""
  FL_EXTRA=""
  if [ -f "$UNITS_HASH/md5.ppu" ] && [ -f "$UNITS_HASH/sha1.ppu" ]; then
    FEATURES="$FEATURES -dMD5"
    FU_EXTRA="$FU_EXTRA -Fu$UNITS_HASH"
    echo "MD5/SHA1 enabled."
  else
    echo "md5/sha1 units not found - building without -dMD5." >&2
  fi
  [ -d "$UNITS_OBJPAS" ] && FU_EXTRA="$FU_EXTRA -Fu$UNITS_OBJPAS"
  # --- Optional: Fun getapi() on macOS via libffi (opt-in, like Linux) ------
  # Needs FPC's ffi unit and a libffi linker stub. Both come from
  # bootstrap-darwin-cross.sh when DARWIN_SDK points at a MacOSX*.sdk; without
  # them the interpreter still builds, just without getapi.
  if [ -f "$UNITS_FFI/ffi.ppu" ] && [ -f "$FFI_LIBDIR/libffi.tbd" ]; then
    FEATURES="$FEATURES -dDarwinFFI"
    FU_EXTRA="$FU_EXTRA -Fu$UNITS_FFI -Fu$HERE/../../lib"
    FL_EXTRA="$FL_EXTRA -Fl$FFI_LIBDIR"
    echo "FFI enabled (getapi via libffi)."
  else
    echo "libffi units/stub not found - building WITHOUT FFI (getapi disabled on macOS)." >&2
  fi
  if [ -f "$PCRE_LIB/libpcre.a" ]; then
    FEATURES="$FEATURES -dRegex"
    FL_EXTRA="$FL_EXTRA -Fl$PCRE_LIB"
    echo "Regex enabled (PCRE 8)."
  else
    echo "PCRE for darwin not found - building WITHOUT regex." >&2
  fi

  # --- Build ----------------------------------------------------------------
  BUILD="$(mktemp -d "${TMPDIR:-/tmp}/fun-darwin-build-$cpu-XXXXXX")"
  echo "Building funcmd for darwin/$cpu with $PPCROSS"
  # -n: ignore the host fpc.cfg (its unit paths are for the build host)
  # -FD: pin clang/ld/fpcres to our shims
  # shellcheck disable=SC2086
  "$PPCROSS" funcmd.dpr -n -B -Sd -O2 -Xs -XX -Tdarwin -dDarwin \
      -Fu"$UNITS" $FU_EXTRA $FL_EXTRA -FD"$TOOLS" \
      -FU"$BUILD" -FE"$BUILD" $FEATURES "$@"

  OUT="${FUN_DARWIN_OUT:-$HERE/../../../fun/funcmd-darwin-$cpu}"
  cp -f "$BUILD/funcmd" "$OUT"
  echo "Copied funcmd to $OUT"
  rm -rf "$BUILD"
}

if [ "$CPU" = all ]; then
  build_cpu x86_64 "$@"
  build_cpu aarch64 "$@"
else
  build_cpu "$CPU" "$@"
fi
