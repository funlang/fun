#!/bin/sh
# ============================================================
# asm-loongarch64-diff: differential check of the LoongArch64 backend against
# the GNU cross assembler.
#
# Every encoding lib-asm-loongarch64 emits must be byte-for-byte what
# `loongarch64-linux-gnu-as` produces for the same instruction, including the
# multi-instruction `li.w` / `li.d` expansions. This runs both sides over
# fun/test/tools/loongarch64-cases.txt and reports mismatches.
#
# Usage, from the repository root:
#   fun/test/tools/asm-loongarch64-diff.sh [cases-file]
#
# Needs `loongarch64-linux-gnu-as` and `loongarch64-linux-gnu-objdump`
# (Debian/Ubuntu: binutils-loongarch64-linux-gnu; or a source-built binutils).
# If they are missing the script prints a skip line and exits 0, so it is safe
# to call unconditionally.
#
# Branch cases use the backend's `#byte-offset` spelling; the GNU assembler
# takes a plain address/expression, so the '#' is stripped before assembling.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
FUNCMD="${FUNCMD:-$ROOT/src/prj/fun/funcmd}"
CASES="${1:-$ROOT/fun/test/tools/loongarch64-cases.txt}"

AS="${LA_AS:-loongarch64-linux-gnu-as}"
OD="${LA_OBJDUMP:-loongarch64-linux-gnu-objdump}"

if [ ! -x "$FUNCMD" ]; then
    echo "funcmd not found at $FUNCMD (build it first)" >&2
    exit 2
fi
if ! command -v "$AS" >/dev/null 2>&1 || ! command -v "$OD" >/dev/null 2>&1; then
    echo "SKIP asm-loongarch64-diff: '$AS' / '$OD' not found (install binutils-loongarch64-linux-gnu)"
    exit 0
fi
if [ ! -f "$CASES" ]; then
    echo "cases file not found: $CASES" >&2
    exit 2
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# our side: "instruction<TAB>hex" per line
(cd "$ROOT" && "$FUNCMD" fun/test/tools/loongarch64-encode.fun "$CASES") > "$TMP/fun.txt"

n=0; bad=0; skip=0
TAB="$(printf '\t')"
while IFS="$TAB" read -r ins hex; do
    [ -z "$ins" ] && continue
    hex="$(printf '%s' "$hex" | tr -d '\r')"   # Fun's Println ends lines with CRLF
    n=$((n + 1))
    # Translate the backend's "#byte-offset" into a gas PC-relative
    # expression (.+N / .-N); gas rejects a bare "#N" branch operand and
    # only accepts a plain address for some alias branches.
    printf '%s\n' "$ins" \
        | sed 's/ #-\([0-9][0-9]*\)/ .-\1/g; s/ #\(-\{0,1\}[0-9][0-9]*\)/ .+\1/g' \
        > "$TMP/ins.s"
    printf '.text\n' > "$TMP/one.s"
    cat "$TMP/ins.s" >> "$TMP/one.s"
    if ! "$AS" -o "$TMP/one.o" "$TMP/one.s" 2>/dev/null; then
        echo "AS-REJECT  $ins"
        skip=$((skip + 1))
        continue
    fi
    # instruction words in order, as 8 upper-case hex digits each
    want="$("$OD" -d "$TMP/one.o" \
            | awk -F'\t' '/^[ \t]*[0-9a-f]+:/{gsub(/ /,"",$2); print $2}' \
            | tr -d ' ' | tr 'a-f' 'A-F' | tr -d '\n')"
    # our hex is little-endian bytes; reverse each 4-byte group to words
    fun_norm="$(printf '%s' "$hex" \
            | awk '{s=$0; for(i=1;i<=length(s);i+=8){c=substr(s,i,8);
                     print substr(c,7,2) substr(c,5,2) substr(c,3,2) substr(c,1,2)}}' \
            | tr -d '\n' | tr 'a-f' 'A-F')"
    if [ "$want" = "$fun_norm" ]; then
        :
    else
        echo "MISMATCH   $ins  fun=$fun_norm  as=$want"
        bad=$((bad + 1))
    fi
done < "$TMP/fun.txt"

echo "asm-loongarch64-diff: $n cases, $bad mismatches, $skip assembler-rejected"
[ "$bad" -eq 0 ]
