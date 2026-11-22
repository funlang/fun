#!/usr/bin/env bash
# Check the README and docs tree.
#
# Validates relative links, in-document anchors, cross-document anchors and
# paired code fences. It does not build Fun; docs.yml runs it before the
# heavier regression jobs.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)
cd "$ROOT" || exit 1

python3 - <<'PY'
import glob
import os
import re
import sys
import urllib.parse

files = [
    "README.md",
    "README.zh.md",
    "CONTRIBUTING.md",
    "CONTRIBUTING.zh.md",
] + sorted(glob.glob("docs/*.md"))
bad = []


def slug(text):
    text = text.strip().lower()
    text = text.replace("`", "")
    text = re.sub(r"[^\w\u4e00-\u9fff\- ]", "", text)
    return text.replace(" ", "-")


def anchors(path):
    result = set()
    in_code = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip().startswith("```"):
                in_code = not in_code
                continue
            if in_code:
                continue
            m = re.match(r"#{1,6}\s+(.*)", line)
            if m:
                result.add(slug(m.group(1)))
    return result


cache = {}


def file_anchors(path):
    if path not in cache:
        cache[path] = anchors(path)
    return cache[path]


for path in files:
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    fences = [i + 1 for i, line in enumerate(lines) if line.strip().startswith("```")]
    if len(fences) % 2:
        bad.append(f"{path}: unpaired code fences ({len(fences)})")

    for m in re.finditer(r"(?<!\!)\[([^\]\n]*)\]\(([^)\n]+)\)", text):
        target = m.group(2).strip()
        if not target or target.startswith(("http://", "https://", "mailto:")):
            continue

        raw_path, _, anchor = target.partition("#")
        if not raw_path:
            if anchor and urllib.parse.unquote(anchor) not in file_anchors(path):
                bad.append(f"{path}: missing anchor #{anchor}")
            continue

        full = os.path.normpath(
            os.path.join(os.path.dirname(path), urllib.parse.unquote(raw_path))
        )
        if not os.path.exists(full):
            bad.append(f"{path}: missing link target {raw_path}")
            continue
        if anchor and full.endswith(".md"):
            if urllib.parse.unquote(anchor) not in file_anchors(full):
                bad.append(f"{path}: missing anchor {raw_path}#{anchor}")

if bad:
    for item in bad:
        print(f"docs: {item}", file=sys.stderr)
    print("docs: FAILED", file=sys.stderr)
    sys.exit(1)
print(f"docs: OK ({len(files)} files)")
PY
