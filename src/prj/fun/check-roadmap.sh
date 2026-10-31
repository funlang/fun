#!/usr/bin/env bash
# Check the master status document.
#
# Validates structure, stable IDs, status vocabulary, the baseline version, and
# the repo-local paths it references. Local-only notes under art/, known-issues/
# and publish/ are skipped when those directories are absent (a fresh clone or
# CI checkout does not have them); when present, their paths are checked.
#
# The regression/loadcheck numbers in ROADMAP.md are runtime facts: the release
# checklist and the regression job own those, this script only checks that the
# document has the expected shape.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT"
DOC=${ROADMAP_DOC:-ROADMAP.md}

fail=0
err() {
  echo "roadmap: $*" >&2
  fail=1
}

if [ ! -f "$DOC" ]; then
  echo "roadmap: $DOC not found" >&2
  exit 1
fi

# ---------------------------------------------------------------- structure
for heading in \
  '## 0. 当前基线' \
  '## 1. 正在进行' \
  '## 2. 下一步' \
  '## 3. 以后' \
  '## 4. 技术债台账' \
  '## 5. 接受 / 不做' \
  '## 6. 发版检查' \
  '## 7. 变更记录'
do
  grep -Fq "$heading" "$DOC" || err "missing heading: $heading"
done

fences=$(grep -c '^```' "$DOC" || true)
[ $((fences % 2)) -eq 0 ] || err "unpaired code fences ($fences)"

# ------------------------------------------------------------ IDs and status
id_lines=$(grep -E '^\|[[:space:]]*[A-Z]+-[0-9]+[[:space:]]*\|' "$DOC" || true)
if [ -z "$id_lines" ]; then
  err "no stable IDs found in tables"
else
  ids=$(printf '%s\n' "$id_lines" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}')
  dups=$(printf '%s\n' "$ids" | sort | uniq -d)
  [ -z "$dups" ] || err "duplicate IDs: $(echo "$dups" | tr '\n' ' ')"

  bad_status=$(printf '%s\n' "$id_lines" | awk -F'|' '
    {
      id=$2; gsub(/^[ \t]+|[ \t]+$/, "", id)
      ok=0
      for (i=3; i<=NF; i++) {
        v=$i; gsub(/^[ \t]+|[ \t]+$/, "", v)
        if (v=="OPEN" || v=="DOING" || v=="BLOCKED" || v=="DONE" || v=="DEFERRED" || v=="WONTFIX") ok=1
      }
      if (!ok) print id
    }')
  [ -z "$bad_status" ] || err "IDs without a valid status: $(echo "$bad_status" | tr '\n' ' ')"
fi

done_in_plan=$(awk '
  /^## 1\./ {sec="NOW"}
  /^## 2\./ {sec="NEXT"}
  /^## 3\./ {sec="LATER"}
  /^## 4\./ {sec=""}
  sec!="" && /\|[[:space:]]*DONE[[:space:]]*\|/ {print sec ": " $0}
' "$DOC")
[ -z "$done_in_plan" ] || err "DONE item left in a planning section: $done_in_plan"

# --------------------------------------------------------------- version
version_inc=$(sed -n "s/.*funRelease = '\([0-9][0-9.]*\)'.*/\1/p" src/core/version.inc | head -1)
changelog_version=$(grep -m1 '^## \[[0-9]' CHANGELOG.md | sed 's/^## \[\([^]]*\)\].*/\1/')
roadmap_version=$(grep -m1 '基线：Fun ' "$DOC" | sed 's/.*Fun \([0-9][0-9.]*\).*/\1/')

[ -n "$version_inc" ] || err "cannot read funRelease from src/core/version.inc"
[ -n "$changelog_version" ] || err "cannot read the latest version from CHANGELOG.md"
[ -n "$roadmap_version" ] || err "cannot read the baseline version from $DOC"
if [ -n "$version_inc" ] && [ -n "$changelog_version" ] && [ -n "$roadmap_version" ]; then
  [ "$version_inc" = "$changelog_version" ] || \
    err "version mismatch: version.inc=$version_inc CHANGELOG=$changelog_version"
  [ "$version_inc" = "$roadmap_version" ] || \
    err "version mismatch: version.inc=$version_inc ROADMAP=$roadmap_version"
fi

# ------------------------------------------------------- referenced paths
# Backticked spans that look like repo paths. Skip prose, patterns, refs/ and
# local-only note trees when those trees are not present.
paths=$(grep -oE '`[^`]+`' "$DOC" | tr -d '`' | sort -u)
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    *:*) continue ;;
    *' '*|*'*'*|*'<'*|*'>'*|*'?'*|*'$'*) continue ;;
    [0-9]*/[0-9]*) continue ;;
    */*) ;;
    *) continue ;;
  esac
  case "$p" in
    refs/*) continue ;;
    art/*|known-issues/*|publish/*)
      dir=${p%%/*}
      [ -d "$dir" ] || continue
      ;;
  esac
  [ -e "$p" ] || err "missing referenced path: $p"
done <<EOF
$paths
EOF

if [ "$fail" -eq 0 ]; then
  echo "roadmap: OK"
  exit 0
fi
echo "roadmap: FAILED" >&2
exit 1
