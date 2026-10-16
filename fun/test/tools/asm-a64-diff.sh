#!/bin/sh
# ============================================================
# asm-a64-diff: differential check of the aarch64 backend against the GNU
# cross assembler.
#
# The encodings lib-asm-a64 emits must be byte-for-byte what
# `gcc-aarch64-linux-gnu-as` / gas produce for the same instructions. This
# runs both sides over fun/test/tools/a64-cases.txt and reports mismatches.
#
# Usage, from the repository root:
#   fun/test/tools/asm-a64-diff.sh [cases-file]
#
# Needs `arch64-linux-gnu-as` and `arch64-linux-gnu-objdump` (Debian/Ubuntu:
# gcc-aarch64-linux-gnu + binutils-aarch64-linux-gnu). If they are missing the
# script prints a skip line and exits 0, so it is safe to call unconditionally.
#
# The x86 assembler table was generated with the same method (assemble, dump
# .text, compare) back when asm-list.fd was built.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
FUNCMD="$ROOT/src/prj/fun/funcmd"
CASES="${1:-$ROOT/fun/test/tools/a64-cases.txt}"

AS="${A64_AS:-arch64-linux-gnu-as}"
OD="${A64_OBJDUMP:-arch64-linux-gnu-objdump}"

if [ ! -x "$FUNCMD" ]; then
    echo "funcmd not found at $FUNCMD (build it first)" >&2
    exit 2
fi
if ! command -v "$AS" >/dev/null 2>&1 || ! command -v "$OD" >/dev/null 2>&1; then
    echo "SKIP asm-a64-diff: '$AS' / '$OD' not found (install gcc-aarch64-linux-gnu)"
    exit 0
fi
if [ ! -f "$CASES" ]; then
    echo "cases file not found: $CASES" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# our side: "instruction<TAB>hex" per line
(cd "$ROOT" && "$FUNCMD" fun/test/tools/a64-encode.fun "$CASES") > "$TMP/fun.txt"

n=0; bad=0; skip=0
TAB="$(printf '\t')"
while IFS="$TAB" read -r ins hex; do
    [ -z "$ins" ] && continue
    hex="$(printf '%s' "$hex" | tr -d '\r')"   # Fun's Println ends lines with CRLF
    n=$((n + 1))
    printf '.text\n%s\n' "$ins" > "$TMP/one.s"
    if ! "$AS" -o "$TMP/one.o" "$TMP/one.s" 2>/dev/null; then
        echo "AS-REJECT  $ins"
        skip=$((skip + 1))
        continue
    fi
    # raw instruction bytes: field 2 of the disassembly line, spaces removed
    want="$("$OD" -d "$TMP/one.o" \
            | awk -F'\t' '/^[ \t]*[0-9a-f]+:/{gsub(/ /,"",$2); print $2; exit}' \
            | tr -d ' ' | tr 'a-f' 'A-F')"
    # objdump prints the 4-byte instruction as spaced octets (memory order) on
    # some builds and as the whole word on others; accept either orientation.
    fun_hex="$(printf '%s' "$hex" | tr 'a-f' 'A-F')"
    fun_rev="$(printf '%s' "$fun_hex" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/')"
    if [ "$want" = "$fun_hex" ] || [ "$want" = "$fun_rev" ]; then
        :
    else
        echo "MISMATCH   $ins  fun=$hex  as=$want"
        bad=$((bad + 1))
    fi
done < "$TMP/fun.txt"

echo "asm-a64-diff: $n cases, $bad mismatches, $skip assembler-rejected"
[ "$bad" -eq 0 ]
