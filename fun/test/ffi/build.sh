#!/bin/sh
# ============================================================
# Build the FFI test helper library for the host.
#
# fun/test/ffi/ffi-*.fun call into libffitest through getapi(). The compiled
# library is not tracked (it is a build artifact, *.so / *.dylib), so this
# builds it on demand:
#
#   Linux  -> libffitest.so    (cc -fPIC -shared)
#   macOS  -> libffitest.dylib (cc -fPIC -dynamiclib)
#   Windows-> libffitest.dll   (gcc -shared -Wl,--export-all-symbols, from an
#                               MSYS/MinGW shell; the .dll is what the Windows
#                               runner loads when the build has getapi)
#
# Called automatically by run-linux-regression.sh (and the macOS wrapper) so a
# fresh checkout can run the FFI suite; run it by hand after editing the C file.
# ============================================================
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/libffitest.c"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

CC_BIN=""
for c in "$CC" cc clang gcc; do
    [ -n "$c" ] || continue
    if command -v "$c" >/dev/null 2>&1; then CC_BIN="$c"; break; fi
done
[ -n "$CC_BIN" ] || { echo "no C compiler (cc/clang/gcc) found" >&2; exit 1; }

case "$(uname -s 2>/dev/null)" in
    Darwin) OUT="$HERE/libffitest.dylib"; SHARED="-dynamiclib" ;;
    MINGW*|MSYS*|CYGWIN*)
            # libffitest.c has no __declspec(dllexport), and MinGW exports
            # nothing by default, so the symbols GetProcAddress looks up need
            # --export-all-symbols.
            OUT="$HERE/libffitest.dll"; SHARED="-shared -Wl,--export-all-symbols" ;;
    *)      OUT="$HERE/libffitest.so";    SHARED="-shared" ;;
esac

# Rebuild when the source is newer than the artifact, or when the artifact was
# built for another CPU. The latter happens after a cross/qemu regression run
# (e.g. loongarch64) leaves its libffitest.so behind, and a later native run
# would otherwise load the wrong-architecture library.
if [ -f "$OUT" ] && [ ! "$SRC" -nt "$OUT" ]; then
    host_arch=""
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64)        host_arch='x86-64|x86_64' ;;
        aarch64|arm64)       host_arch='aarch64|arm64' ;;
        loongarch64|loong64) host_arch='LoongArch' ;;
        i?86)                host_arch='80386' ;;
    esac
    if [ -z "$host_arch" ] || ! command -v file >/dev/null 2>&1 || \
       file "$OUT" | grep -qiE "$host_arch"; then
        echo "up to date: $OUT"
        exit 0
    fi
    echo "rebuilding $OUT for $(uname -m)"
fi

"$CC_BIN" -O2 -fPIC $SHARED -o "$OUT" "$SRC"
echo "built $OUT"
