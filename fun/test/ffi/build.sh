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

# Rebuild only when the source is newer than the artifact.
if [ -f "$OUT" ] && [ ! "$SRC" -nt "$OUT" ]; then
    echo "up to date: $OUT"
    exit 0
fi

"$CC_BIN" -O2 -fPIC $SHARED -o "$OUT" "$SRC"
echo "built $OUT"
