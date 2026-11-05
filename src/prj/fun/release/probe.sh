#!/bin/sh
# ============================================================
# probe.sh -- record what a built Fun interpreter can actually do.
#
# The release workflow must never publish a degraded build as if it were the
# full one. This script runs the binary itself (not the build log) and writes
# a machine-readable capabilities file next to the staged artifact.
#
# Usage:
#   src/prj/fun/release/probe.sh <platform> <out.json> \
#       <funcmd> <funcmd-safe> [libtcc]
#
# Example:
#   src/prj/fun/release/probe.sh linux-x64 build-env.json \
#       fun/funcmd fun/funcmd-safe fun/libtcc.so
#
# The probes are deliberately small and self-contained; a missing optional
# dependency is a fact to report, never a failure of this script.
# ============================================================
set -u

PLATFORM=${1:?platform}
OUT=${2:?output json}
FUNCMD=${3:?funcmd path}
SAFE=${4:-}
LIBTCC=${5:-}

COMMIT=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fun-probe-XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT INT TERM

# Normalize runner output: Windows CRLF is not relevant here (POSIX jobs only)
# but keep the check strict anyway.
run_probe() {
    # run_probe <file> -> prints the last non-empty line
    out=$("$FUNCMD" "$1" 2>/dev/null | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -n 1)
    printf '%s' "$out"
}

# --- regex (-dRegex, bundled PCRE) ---------------------------------------
cat > "$TMP/regex.fun" <<'EOF'
try
  var r = 'a1b2'.replace(/\d++/g, '-');
  ?. r;
except
  ?. 'off';
end try;
EOF
regex_out=$(run_probe "$TMP/regex.fun")
if [ "$regex_out" = "a-b-" ]; then REGEX=true; else REGEX=false; fi

# --- FFI / getapi ---------------------------------------------------------
# Linux opens libc.so.6; macOS has libSystem. A build without the FFI backend
# throws before the call, which is exactly what the try block reports.
cat > "$TMP/ffi.fun" <<'EOF'
var f = nil;
try f = 'libc.so.6'.getapi('getpid', ':i'); except f = nil; end try;
if f = nil then
  try f = '/usr/lib/libSystem.B.dylib'.getapi('getpid', ':i'); except f = nil; end try;
end if;
if f <> nil then
  try
    var pid = f();
    if pid > 0 then ?. 'on'; else ?. 'off'; end if;
  except
    ?. 'off';
  end try;
else
  ?. 'off';
end if;
EOF
ffi_out=$(run_probe "$TMP/ffi.fun")
if [ "$ffi_out" = "on" ]; then FFI=true; else FFI=false; fi

# --- runtime C compile via libtcc ---------------------------------------
# ccompile() lives in lib-tcc.fun; the module is found next to the executable
# (fun/lib), which is why the probe is run after the build copies funcmd into
# fun/. Do not even parse the module when the library is absent.
TCC=false
if [ -n "$LIBTCC" ] && [ -f "$LIBTCC" ]; then
    cat > "$TMP/tcc.fun" <<'EOF'
use 'lib-tcc.fun';
try
  var add = ccompile('int add(int a, int b) { return a + b; }', 'ii:i');
  ?. add.call(3, 4);
  add.del();
except
  ?. 'off';
end try;
EOF
    tcc_out=$(run_probe "$TMP/tcc.fun")
    if [ "$tcc_out" = "7" ]; then TCC=true; fi
fi

# --- presence facts ------------------------------------------------------
LIBTCC_PRESENT=false
[ -n "$LIBTCC" ] && [ -f "$LIBTCC" ] && LIBTCC_PRESENT=true
# zlib is only shipped on Windows; on POSIX only report a bundled libz.
ZLIB_PRESENT=false
for z in "$(dirname "$FUNCMD")/libz.so.1" "$(dirname "$FUNCMD")/libz.dylib"; do
    [ -f "$z" ] && ZLIB_PRESENT=true
done
SAFE_PRESENT=false
[ -n "$SAFE" ] && [ -f "$SAFE" ] && SAFE_PRESENT=true

json_bool() { if [ "$1" = true ]; then printf 'true'; else printf 'false'; fi; }

# Build flags are inferred from the probes, not copied from the script, so a
# source/flag drift shows up as a capability mismatch instead of a false claim.
FLAGS="\"-dFunPack\",\"-dCalcOpt\""
[ "$REGEX" = true ] && FLAGS="$FLAGS,\"-dRegex\""
[ "$FFI" = true ] && FLAGS="$FLAGS,\"-dFFI\""

NOTES=""
if [ "$REGEX" = false ]; then NOTES="$NOTES regex unavailable (PCRE source missing or build skipped)."; fi
if [ "$FFI" = false ]; then NOTES="$NOTES getapi/FFI unavailable."; fi
if [ "$TCC" = false ]; then NOTES="$NOTES runtime C compile unavailable (no libtcc)."; fi
NOTES=$(printf '%s' "$NOTES" | sed 's/^ //')

cat > "$OUT" <<EOF
{
  "platform": "$PLATFORM",
  "commit_sha": "$COMMIT",
  "tag": "",
  "build_flags": [$FLAGS],
  "regex": $(json_bool "$REGEX"),
  "ffi": $(json_bool "$FFI"),
  "tcc": $(json_bool "$TCC"),
  "asm": true,
  "safe": $(json_bool "$SAFE_PRESENT"),
  "safe_level": "strict",
  "libtcc_present": $(json_bool "$LIBTCC_PRESENT"),
  "zlib_present": $(json_bool "$ZLIB_PRESENT"),
  "notes": "$NOTES"
}
EOF

echo "probe: $PLATFORM regex=$REGEX ffi=$FFI tcc=$TCC safe=$SAFE_PRESENT"
