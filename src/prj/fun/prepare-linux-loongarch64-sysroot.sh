#!/bin/sh
# ============================================================
# prepare-linux-loongarch64-sysroot.sh -- download the Alpine loongarch64
# runtime needed by the full (libc/FFI/regex) cross build.
#
# The default cross build is self-contained and syscall based. This script
# supplies the extra target libraries for the "full" build:
#   - musl libc and headers
#   - libffi (getapi / @toCallback)
#   - PCRE 8 (regex)
#   - zlib, OpenSSL, libcurl, SQLite, libxml2 (the -lnx standard-library
#     backends)
#   - libgcc_s (__clear_cache, used by lib-asm-loongarch64 to flush the
#     instruction cache after writing JIT code; musl's libc does not export it)
#
# It extracts Alpine's prebuilt loongarch64 packages into a plain directory,
# so no root, no chroot and no package manager are needed on the host.
#
# Usage:
#   ./prepare-linux-loongarch64-sysroot.sh
#   LOONG_SYSROOT=/opt/loong-sysroot ./prepare-linux-loongarch64-sysroot.sh
#
# Output ($LOONG_SYSROOT, default ~/.fun/linux-loongarch64-sysroot):
#   lib/ld-musl-loongarch64.so.1
#   lib/libc.musl-loongarch64.so.1
#   usr/lib/libffi.so.8, libpcre.so.1, libz.so.1, ...
#   usr/include/{ffi.h,pcre.h,...}
#
# Then:
#   FPC_USE_LIBC=1 ./bootstrap-linux-loongarch64.sh
#   FULL=1 LOONG_SYSROOT=... ./make-linux-loongarch64.sh
#   LOONG_SYSROOT=... ./../test/run-loongarch64-qemu.sh
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

ALPINE_VER="${ALPINE_VER:-v3.21}"
ALPINE_ARCH=loongarch64
MIRROR="${ALPINE_MIRROR:-https://dl-cdn.alpinelinux.org/alpine}"
ROOT="${LOONG_SYSROOT:-$HOME/.fun/linux-loongarch64-sysroot}"
DL="$ROOT/.apk"
IDX="$DL/APKINDEX"

PACKAGES="musl musl-dev libffi libffi-dev pcre pcre-dev \
          zlib libcrypto3 libssl3 sqlite-libs libxml2 xz-libs \
          libcurl brotli-libs c-ares nghttp2-libs libpsl zstd-libs \
          libidn2 libunistring libgcc"

fetch() {
    url="$1"; out="$2"
    [ -f "$out" ] && return 0
    echo "Downloading $(basename "$out")"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 -o "$out" "$url"
    else
        wget -O "$out" "$url"
    fi
}

mkdir -p "$DL" "$ROOT"

echo "Fetching Alpine $ALPINE_VER/$ALPINE_ARCH package index"
fetch "$MIRROR/$ALPINE_VER/main/$ALPINE_ARCH/APKINDEX.tar.gz" "$DL/APKINDEX.tar.gz"
tar xzf "$DL/APKINDEX.tar.gz" -C "$DL" APKINDEX

pkgver() {
    awk -v p="$1" 'BEGIN{RS="";FS="\n"}
        $0 ~ "\nP:"p"\n" { for(i=1;i<=NF;i++) if($i ~ /^V:/){ print substr($i,3) } }' \
        "$IDX" | head -n 1
}

for p in $PACKAGES; do
    v="$(pkgver "$p")"
    [ -n "$v" ] || { echo "prepare: package $p not found in index" >&2; exit 1; }
    apk="$p-$v.apk"
    fetch "$MIRROR/$ALPINE_VER/main/$ALPINE_ARCH/$apk" "$DL/$apk"
    # The APK signature member makes tar return a non-zero status on some tar
    # versions even though every file was extracted; the files are what matter.
    tar xzf "$DL/$apk" -C "$ROOT" 2>/dev/null || true
done

# The musl loader is both the dynamic linker and libc.so.  Standard programs
# and FPC's dynlibs ask for the glibc-style names (libc.so.6, libm.so.6, ...),
# so provide compatibility links inside the sysroot.
mkdir -p "$ROOT/lib64"
for n in libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libutil.so.1; do
    ln -sf libc.musl-loongarch64.so.1 "$ROOT/lib/$n"
done
ln -sf ../lib/ld-musl-loongarch64.so.1 "$ROOT/lib64/ld-linux-loongarch-lp64d.so.1"
ln -sf ../../lib/ld-musl-loongarch64.so.1 "$ROOT/usr/lib/libdl.so"

[ -f "$ROOT/lib/ld-musl-loongarch64.so.1" ] || {
    echo "prepare: musl loader missing under $ROOT" >&2; exit 1; }
[ -f "$ROOT/usr/lib/libffi.so.8" ] || {
    echo "prepare: libffi missing under $ROOT" >&2; exit 1; }
[ -f "$ROOT/usr/lib/libpcre.so.1" ] || {
    echo "prepare: PCRE missing under $ROOT" >&2; exit 1; }

echo
echo "LoongArch64 musl sysroot ready under: $ROOT"
echo "Build the full interpreter with:"
echo "  FPC_USE_LIBC=1 ./bootstrap-linux-loongarch64.sh"
echo "  FULL=1 LOONG_SYSROOT=$ROOT ./make-linux-loongarch64.sh"
