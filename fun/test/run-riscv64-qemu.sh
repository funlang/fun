#!/bin/sh
# ============================================================
# run-riscv64-qemu.sh -- run the Linux regression against the
# riscv64 musl cross build under qemu-user.
#
# This is the emulated counterpart of run-linux-regression.sh. It builds the
# FFI helper library for riscv64, wraps funcmd in qemu, and uses the
# linux-riscv64-qemu skip list (the x86-64/aarch64 asm backends, ODBC, and
# the shell-based project tests that invoke the target binary directly). There
# is no riscv64 JIT backend, so the assembly tests are skipped too.
#
# Usage:
#   RISCV_SYSROOT=~/.fun/linux-riscv64-sysroot ./run-riscv64-qemu.sh
#   FUNCMD=/path/to/funcmd-linux-riscv64-musl \
#   QEMU_RISCV64=/path/to/qemu-riscv64-static \
#   ZIG=/path/to/zig \
#   RISCV_LD=/path/to/riscv64-linux-ld \
#   ./run-riscv64-qemu.sh
#
# Needs: qemu-riscv64-static (or qemu-riscv64), Zig 0.13 (to build
# libffitest.so for the target), and the full cross build from
# make-linux-riscv64.sh (FULL=1).
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

SYSROOT="${RISCV_SYSROOT:-$HOME/.fun/linux-riscv64-sysroot}"
FUNCMD="${FUNCMD:-$ROOT/fun/funcmd-linux-riscv64-musl}"
ZIG="${ZIG:-$(command -v zig 2>/dev/null || true)}"
RISCV_FPC_ROOT="${RISCV_FPC_ROOT:-$HOME/.fun/linux-riscv64}"
RISCV_LD="${RISCV_LD:-$RISCV_FPC_ROOT/tools/riscv64-linux-ld}"
QEMU="${QEMU_RISCV64:-$(command -v qemu-riscv64-static 2>/dev/null || command -v qemu-riscv64 2>/dev/null || true)}"

[ -x "$FUNCMD" ] || { echo "funcmd not found: $FUNCMD" >&2
                      echo "Build it with FULL=1 make-linux-riscv64.sh." >&2; exit 1; }
[ -d "$SYSROOT" ] || { echo "musl sysroot not found: $SYSROOT" >&2
                      echo "Run prepare-linux-riscv64-sysroot.sh." >&2; exit 1; }
[ -n "$QEMU" ] || { echo "qemu-riscv64 not found (set QEMU_RISCV64)" >&2; exit 1; }
[ -n "$ZIG" ] || { echo "zig not found (needed for the target libffitest.so)" >&2; exit 1; }
[ -x "$RISCV_LD" ] || { echo "riscv64 linker not found: $RISCV_LD" >&2
                        echo "Set RISCV_LD or RISCV_FPC_ROOT." >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/fun-riscv-qemu-XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# The FFI suite loads fun/test/ffi/libffitest.so. The normal build.sh would
# produce a host (x86_64) library, so compile it for riscv64 here and mark
# it newer than the source so build.sh leaves it alone.
FFI_SRC="$ROOT/fun/test/ffi/libffitest.c"
FFI_OUT="$ROOT/fun/test/ffi/libffitest.so"
if [ -f "$FFI_SRC" ]; then
    echo "Building riscv64 libffitest.so"
    "$ZIG" cc -target riscv64-linux-musl -O2 -fPIC -c "$FFI_SRC" -o "$TMP/libffitest.o"
    "$RISCV_LD" -shared -o "$FFI_OUT" "$TMP/libffitest.o" \
        -L"$SYSROOT/usr/lib" -L"$SYSROOT/lib" -lc
    touch "$FFI_OUT"
fi

cat > "$TMP/funcmd" <<EOF
#!/bin/sh
QEMU_LD_PREFIX="$SYSROOT" exec "$QEMU" "$FUNCMD" "\$@"
EOF
chmod +x "$TMP/funcmd"

FUNCMD="$TMP/funcmd" FUNREG_PLATFORM=linux-riscv64-qemu \
FUNREG_NO_FFI_BUILD=1 \
    sh "$HERE/run-linux-regression.sh" "$@"
