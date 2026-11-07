#!/bin/sh
# ============================================================
# Fun - build fun-jsbox, the one-shot QuickJS-ng sandbox worker.
#
# The worker is a separate executable, not part of funcmd. It links only the
# QuickJS-ng core (quickjs.c, libregexp.c, libunicode.c, dtoa.c), not
# quickjs-libc, so JavaScript code has no console, module loader, file, or
# process API.
#
# Usage:
#   src/prj/fun/build-jsbox.sh
#   CC=clang src/prj/fun/build-jsbox.sh
#   QJS_SRC=/path/to/quickjs-ng src/prj/fun/build-jsbox.sh
#   OUT=/tmp/fun-jsbox src/prj/fun/build-jsbox.sh
#
# Pinned source: QuickJS-ng v0.18.0. The tarball is fetched on demand into
# src/3rd/quickjs-ng (gitignored) and verified against a SHA256. Set QJS_SRC
# to build against another checkout; it must contain quickjs.c.
# ============================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
THIRD="$ROOT/src/3rd"

QJS_VERSION="v0.18.0"
QJS_URL="https://github.com/quickjs-ng/quickjs/archive/refs/tags/${QJS_VERSION}.tar.gz"
QJS_SHA256="28bcd89aa3683fd2a946537e5ce3f11cc46b5cbf3383c7561aaef3df5ff9f1dd"

QJS_SRC="${QJS_SRC:-$THIRD/quickjs-ng}"
OUT="${OUT:-$ROOT/fun/fun-jsbox}"
OBJ="${OBJ:-$HERE/.jsbox-obj}"
CC="${CC:-gcc}"
EXTRA_CFLAGS="${EXTRA_CFLAGS:-}"

OS="$(uname -s 2>/dev/null || echo unknown)"
case "$OS" in
    Darwin) LDLIBS="-lm -lpthread" ;;
    *)      LDLIBS="-lm -ldl -lpthread" ;;
esac

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo "warning: no sha256sum/shasum; cannot verify QuickJS-ng" >&2
        return 0
    fi
}

fetch_qjs() {
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/fun-qjs-XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    archive="$tmp/quickjs-ng.tar.gz"

    echo "fetch   $QJS_URL"
    if command -v curl >/dev/null 2>&1; then
        # --retry-all-errors is not available in older curl (e.g. CentOS 7);
        # --retry still covers transient HTTP status failures.
        curl -fsSL --retry 5 --retry-delay 5 -o "$archive" "$QJS_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=5 --waitretry=5 -O "$archive" "$QJS_URL"
    else
        echo "build-jsbox: need curl or wget to fetch $QJS_URL" >&2
        exit 1
    fi

    actual="$(sha256_of "$archive")"
    if [ -n "$actual" ] && [ "$actual" != "$QJS_SHA256" ]; then
        echo "build-jsbox: SHA256 mismatch for QuickJS-ng" >&2
        echo "  expected $QJS_SHA256" >&2
        echo "  actual   $actual" >&2
        exit 1
    fi

    echo "extract $QJS_VERSION"
    tar -xzf "$archive" -C "$tmp"
    src="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
    [ -n "$src" ] || { echo "build-jsbox: unexpected archive layout" >&2; exit 1; }
    rm -rf "$QJS_SRC"
    mkdir -p "$THIRD"
    mv "$src" "$QJS_SRC"
    rm -rf "$tmp"
    trap - EXIT INT TERM
    echo "done    src/3rd/quickjs-ng"
}

if [ ! -f "$QJS_SRC/quickjs.c" ]; then
    if [ "$QJS_SRC" != "$THIRD/quickjs-ng" ]; then
        echo "build-jsbox: QJS_SRC=$QJS_SRC does not contain quickjs.c" >&2
        exit 1
    fi
    fetch_qjs
fi

mkdir -p "$OBJ"
CFLAGS_BASE="-std=gnu11 -O2 -fPIE -D_GNU_SOURCE"
STAMP="$OBJ/.buildflags"
STAMP_VALUE="$CC|$QJS_SRC|$CFLAGS_BASE|$EXTRA_CFLAGS"
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$STAMP_VALUE" ]; then
    rm -f "$OBJ"/*.o
    printf '%s\n' "$STAMP_VALUE" > "$STAMP"
fi

echo "Building fun-jsbox from $QJS_SRC"
for f in quickjs libregexp libunicode dtoa; do
    if [ ! -f "$OBJ/$f.o" ] || [ "$QJS_SRC/$f.c" -nt "$OBJ/$f.o" ]; then
        echo "  cc    $f.c"
        $CC $CFLAGS_BASE $EXTRA_CFLAGS -I"$QJS_SRC" -c "$QJS_SRC/$f.c" -o "$OBJ/$f.o"
    fi
done

if [ ! -f "$OBJ/jsbox-main.o" ] || [ "$HERE/jsbox/main.c" -nt "$OBJ/jsbox-main.o" ]; then
    echo "  cc    jsbox/main.c"
    $CC $CFLAGS_BASE $EXTRA_CFLAGS -I"$QJS_SRC" -Wall -Wextra -c "$HERE/jsbox/main.c" -o "$OBJ/jsbox-main.o"
fi

echo "  link  $OUT"
mkdir -p "$(dirname "$OUT")"
$CC -pie -o "$OUT" \
    "$OBJ/quickjs.o" "$OBJ/libregexp.o" "$OBJ/libunicode.o" "$OBJ/dtoa.o" \
    "$OBJ/jsbox-main.o" $LDLIBS
chmod +x "$OUT"
echo "built $OUT"
