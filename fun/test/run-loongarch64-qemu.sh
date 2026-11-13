#!/bin/sh
# ============================================================
# run-loongarch64-qemu.sh -- run the Linux regression against the
# loongarch64 musl cross build under qemu-user.
#
# This is the emulated counterpart of run-linux-regression.sh. It builds the
# FFI helper library for loongarch64, wraps funcmd in qemu, and uses the
# linux-loongarch64-qemu skip list (the x86-64/aarch64 asm backends, ODBC, and
# the shell-based project tests that invoke the target binary directly). The
# LoongArch asm backend itself runs, including its live JIT call.
#
# Usage:
#   LOONG_SYSROOT=~/.fun/linux-loongarch64-sysroot ./run-loongarch64-qemu.sh
#   FUNCMD=/path/to/funcmd-linux-loongarch64-musl \
#   QEMU_LOONGARCH64=/path/to/qemu-loongarch64-static \
#   ZIG=/path/to/zig \
#   LOONG_LD=/path/to/loongarch64-linux-ld \
#   ./run-loongarch64-qemu.sh
#
# Needs: qemu-loongarch64-static (or qemu-loongarch64), Zig 0.13 (to build
# libffitest.so for the target), and the full cross build from
# make-linux-loongarch64.sh (FULL=1).
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

SYSROOT="${LOONG_SYSROOT:-$HOME/.fun/linux-loongarch64-sysroot}"
FUNCMD="${FUNCMD:-$ROOT/fun/funcmd-linux-loongarch64-musl}"
ZIG="${ZIG:-$(command -v zig 2>/dev/null || true)}"
LOONG_FPC_ROOT="${LOONG_FPC_ROOT:-$HOME/.fun/linux-loongarch64}"
LOONG_LD="${LOONG_LD:-$LOONG_FPC_ROOT/tools/loongarch64-linux-ld}"
QEMU="${QEMU_LOONGARCH64:-$(command -v qemu-loongarch64-static 2>/dev/null || command -v qemu-loongarch64 2>/dev/null || true)}"

[ -x "$FUNCMD" ] || { echo "funcmd not found: $FUNCMD" >&2
                      echo "Build it with FULL=1 make-linux-loongarch64.sh." >&2; exit 1; }
[ -d "$SYSROOT" ] || { echo "musl sysroot not found: $SYSROOT" >&2
                      echo "Run prepare-linux-loongarch64-sysroot.sh." >&2; exit 1; }
[ -n "$QEMU" ] || { echo "qemu-loongarch64 not found (set QEMU_LOONGARCH64)" >&2; exit 1; }
[ -n "$ZIG" ] || { echo "zig not found (needed for the target libffitest.so)" >&2; exit 1; }
[ -x "$LOONG_LD" ] || { echo "loongarch64 linker not found: $LOONG_LD" >&2
                        echo "Set LOONG_LD or LOONG_FPC_ROOT." >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fun-loong-qemu-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The FFI suite loads fun/test/ffi/libffitest.so. The normal build.sh would
# produce a host (x86_64) library, so compile it for loongarch64 here and mark
# it newer than the source so build.sh leaves it alone.
FFI_SRC="$ROOT/fun/test/ffi/libffitest.c"
FFI_OUT="$ROOT/fun/test/ffi/libffitest.so"
if [ -f "$FFI_SRC" ]; then
    echo "Building loongarch64 libffitest.so"
    "$ZIG" cc -target loongarch64-linux-musl -O2 -fPIC -c "$FFI_SRC" -o "$TMP/libffitest.o"
    "$LOONG_LD" -shared -o "$FFI_OUT" "$TMP/libffitest.o" \
        -L"$SYSROOT/usr/lib" -L"$SYSROOT/lib" -lc
    touch "$FFI_OUT"
fi

cat > "$TMP/funcmd" <<EOF
#!/bin/sh
QEMU_LD_PREFIX="$SYSROOT" exec "$QEMU" "$FUNCMD" "\$@"
EOF
chmod +x "$TMP/funcmd"

FUNCMD="$TMP/funcmd" FUNREG_PLATFORM=linux-loongarch64-qemu \
    sh "$HERE/run-linux-regression.sh" "$@"
