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
# Every capability is measured by running the binary, including the machine-code
# (asm) backend: the matching lib-asm backend is asked to JIT a one-line leaf
# function and the result is compared. A target with no backend, or one whose
# icache-flush symbol is missing, reports asm=false instead of inheriting an
# assumption from the build script.
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

# --- machine-code backend via lib-asm -----------------------------------
# JIT one leaf function on the target's own backend: f(n) = n + 1. The module
# is found next to the executable (fun/lib), like lib-tcc above. A wrong or
# missing backend raises in Load(), and a missing __clear_cache raises too
# (lib-asm-loongarch64 refuses to run unflushed code), so both report false.
ASM=false
case "$PLATFORM" in
    *-x64|*-x86_64|*-amd64)     asm_arch=x64 ;;
    *-arm64|*-aarch64)          asm_arch=a64 ;;
    *-loongarch64|*-loong64)    asm_arch=loongarch64 ;;
    *)                          asm_arch= ;;
esac
if [ -n "$asm_arch" ]; then
    asm_out=""
    case "$asm_arch" in
    x64)
        cat > "$TMP/asm.fun" <<'EOF'
use 'lib-asm-pro.fun';
try
  var f = Assembly('i:i', `#!asm
mov rax, rdi
inc rax
ret
`);
  f.Load();
  var r = f.Run(41);
  f.Delete();
  ?. r;
except
  ?. 'off';
end try;
EOF
        ;;
    a64)
        cat > "$TMP/asm.fun" <<'EOF'
use 'lib-asm-a64.fun';
try
  Assembly = AssemblyA64;
  var f = Assembly('i:i', `#!asm
add x0, x0, #1
ret
`);
  f.Load();
  var r = f.Run(41);
  f.Delete();
  ?. r;
except
  ?. 'off';
end try;
EOF
        ;;
    loongarch64)
        cat > "$TMP/asm.fun" <<'EOF'
use 'lib-asm-loongarch64.fun';
try
  Assembly = AssemblyLoongArch64;
  var f = Assembly('i:i', `#!asm
addi.d $a0, $a0, 1
ret
`);
  f.Load();
  var r = f.Run(41);
  f.Delete();
  ?. r;
except
  ?. 'off';
end try;
EOF
        ;;
    esac
    asm_out=$(run_probe "$TMP/asm.fun")
    if [ "$asm_out" = "42" ]; then ASM=true; fi
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
if [ "$ASM" != true ]; then NOTES="$NOTES native asm backend unavailable on this target."; fi
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
  "asm": $(json_bool "$ASM"),
  "safe": $(json_bool "$SAFE_PRESENT"),
  "safe_level": "strict",
  "libtcc_present": $(json_bool "$LIBTCC_PRESENT"),
  "zlib_present": $(json_bool "$ZLIB_PRESENT"),
  "notes": "$NOTES"
}
EOF

echo "probe: $PLATFORM regex=$REGEX ffi=$FFI tcc=$TCC asm=$ASM safe=$SAFE_PRESENT"
