#!/bin/sh
# ============================================================
# Fun - build the linux-x64 release artifacts with an old glibc floor.
#
# The normal Linux build uses whatever glibc the build machine has, so an
# artifact built on Ubuntu 24.04 needs GLIBC_2.34. Domestic distros such as
# Kylin V10 and UOS 20 ship glibc 2.28-2.31, which is below that floor.
# Building in an old container moves the floor down to the container's glibc
# (manylinux2014 / CentOS 7 = 2.17) without changing the source.
#
# PCRE and libffi are linked statically by make-linux-x86_64.sh when their
# fetched sources are present, so the binary does not depend on libpcre.so.1
# or libffi.so.N either.
#
# Usage (from the repository root, inside the container):
#   src/prj/fun/build-linux-legacy.sh
#
# Example with Docker:
#   docker run --rm -v "$PWD:/work" -w /work \
#     quay.io/pypa/manylinux2014_x86_64 \
#     ./src/prj/fun/build-linux-legacy.sh
#
# Environment:
#   OUT_DIR      output directory          (default: <repo>/dist-legacy)
#   FLOOR_MAX    maximum GLIBC_ version    (default: 2.17)
#   FPC_PREFIX   compiler install prefix   (default: /opt/fpc-3.2.2)
#   FPC_CACHE    downloaded tarball        (default: /tmp/fpc-3.2.2.tar)
#   FPC_VERSION  compiler version          (default: 3.2.2)
#   FPC_ARCH     compiler target arch       (default: uname -m)
#
# The script is intentionally POSIX sh + coreutils: CentOS 7 and Debian 10
# both have everything it uses.
# ============================================================
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
cd "$ROOT"

FPC_VERSION="${FPC_VERSION:-3.2.2}"
FPC_ARCH="${FPC_ARCH:-$(uname -m)}"
OUT_DIR="${OUT_DIR:-$ROOT/dist-legacy}"
FLOOR_MAX="${FLOOR_MAX:-2.17}"
FPC_PREFIX="${FPC_PREFIX:-/opt/fpc-$FPC_VERSION}"
FPC_CACHE="${FPC_CACHE:-/tmp/fpc-$FPC_VERSION.tar}"

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "$*" >&2; exit 1; }

for tool in curl tar make gcc ar; do
    command -v "$tool" >/dev/null 2>&1 || die "missing required tool: $tool"
done
if ! command -v bzip2 >/dev/null 2>&1; then
    if command -v yum >/dev/null 2>&1; then
        yum install -y bzip2 >/dev/null
    else
        die "missing bzip2 (needed to unpack the TCC source)"
    fi
fi

# --- FPC ------------------------------------------------------------------
# The official Linux tarball is an outer tar of per-package tarballs and an
# interactive install.sh. Extract the packages directly and generate fpc.cfg
# with samplecfg instead: that works non-interactively and does not require
# root. FPC reads $HOME/.fpc.cfg, so HOME is pointed at a scratch directory
# rather than the invoking user's home.
need_fpc=1
if [ -x "$FPC_PREFIX/bin/fpc" ] && [ "$("$FPC_PREFIX/bin/fpc" -iV 2>/dev/null)" = "$FPC_VERSION" ]; then
    need_fpc=0
fi
if [ "$need_fpc" -eq 1 ]; then
    say "Installing FPC $FPC_VERSION ($FPC_ARCH) into $FPC_PREFIX"
    if [ ! -f "$FPC_CACHE" ]; then
        url="https://downloads.sourceforge.net/project/freepascal/Linux/$FPC_VERSION/fpc-$FPC_VERSION.$FPC_ARCH-linux.tar"
        say "  downloading $url"
        # CentOS 7's curl 7.29 predates --retry-all-errors; probe instead of
        # letting the unsupported flag turn into a noisy failed attempt.
        if curl --help 2>&1 | grep -q -- '--retry-all-errors'; then
            curl -fSL --retry 5 --retry-all-errors --retry-delay 5 -o "$FPC_CACHE" "$url"
        else
            curl -fSL --retry 5 --retry-delay 5 -o "$FPC_CACHE" "$url"
        fi
    fi
    work="$(mktemp -d "${TMPDIR:-/tmp}/fun-fpc-XXXXXX")"
    trap 'rm -rf "$work"' EXIT INT TERM
    tar xf "$FPC_CACHE" -C "$work"
    pkgdir="$work/fpc-$FPC_VERSION.$FPC_ARCH-linux"
    [ -f "$pkgdir/binary.$FPC_ARCH-linux.tar" ] || die "unexpected FPC tarball layout"
    inner="$work/inner"
    mkdir -p "$inner"
    tar xf "$pkgdir/binary.$FPC_ARCH-linux.tar" -C "$inner"
    mkdir -p "$FPC_PREFIX"
    tar xzf "$inner/base.$FPC_ARCH-linux.tar.gz" -C "$FPC_PREFIX"
    # units-* are the RTL/packages; utils-fpcmkcfg ships the fpcmkcfg binary
    # that samplecfg invokes. install.sh installs all three groups, so do the
    # same instead of leaving config generation without a tool.
    for t in "$inner"/units-*.tar.gz "$inner"/utils-*.tar.gz; do
        [ -f "$t" ] || continue
        tar xzf "$t" -C "$FPC_PREFIX"
    done
    # install.sh links the compiler driver (ppcx64/ppca64/...) from
    # lib/fpc/<version> into bin/; without it the fpc wrapper exits with
    # "ppcx64 can't be executed, error code: 127".
    for ppc in "$FPC_PREFIX/lib/fpc/$FPC_VERSION"/ppc*; do
        [ -f "$ppc" ] || continue
        ln -sf "$ppc" "$FPC_PREFIX/bin/$(basename "$ppc")"
    done
    rm -rf "$work"
    trap - EXIT INT TERM
fi

FPC_HOME="${FPC_HOME:-/tmp/fun-fpc-home}"
mkdir -p "$FPC_HOME"
# samplecfg calls fpcmkcfg, which ships in $FPC_PREFIX/bin; put it on PATH
# first or config generation fails on a clean container (CentOS 7 has no
# /usr/bin/fpcmkcfg).
export PATH="$FPC_PREFIX/bin:$PATH"
HOME="$FPC_HOME" "$FPC_PREFIX/lib/fpc/$FPC_VERSION/samplecfg" \
    "$FPC_PREFIX/lib/fpc/$FPC_VERSION" >"$FPC_HOME/samplecfg.log" 2>&1 || true
if [ ! -f /etc/fpc.cfg ] && [ ! -f "$FPC_HOME/.fpc.cfg" ]; then
    cat "$FPC_HOME/samplecfg.log" >&2 || true
    die "FPC config generation failed"
fi
export HOME="$FPC_HOME"
export FPC="$FPC_PREFIX/bin/fpc"
say "FPC $("$FPC" -iV) at $FPC_PREFIX"

# --- dependencies and builds ---------------------------------------------
"$ROOT/src/prj/fun/fetch-3rd-party.sh"

say "Building funcmd (default)"
"$ROOT/src/prj/fun/make-linux-x86_64.sh"
say "Building funcmd-safe"
SAFE=strict "$ROOT/src/prj/fun/make-linux-x86_64.sh"
say "Building funcmd-mt"
FUN_THREADS=1 "$ROOT/src/prj/fun/make-linux-x86_64.sh"

# --- verify and collect ----------------------------------------------------
"$ROOT/src/prj/fun/check-linux-floor.sh" --max "$FLOOR_MAX" \
    "$ROOT/src/prj/fun/funcmd" \
    "$ROOT/src/prj/fun/funcmd-safe" \
    "$ROOT/src/prj/fun/funcmd-mt" \
    "$ROOT/src/prj/fun/libtcc.so"

case "$OUT_DIR" in
    ""|/) die "refusing to clear OUT_DIR='$OUT_DIR'" ;;
esac
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
for f in funcmd funcmd-safe funcmd-mt libtcc.so; do
    cp "$ROOT/src/prj/fun/$f" "$OUT_DIR/$f"
done
say "Legacy artifacts in $OUT_DIR"
ls -l "$OUT_DIR"
