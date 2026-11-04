#!/bin/sh
# ============================================================
# install.sh -- install a Fun release for macOS or Linux.
#
# macOS builds are unsigned and not notarized. Downloading with curl does not
# set the com.apple.quarantine attribute, and this script also clears it after
# extraction, so the interpreter starts without a Gatekeeper prompt. No sudo
# is used.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/funlang/fun/main/install.sh | sh
#   curl -fsSL .../install.sh | sh -s -- --tag v9.5.5-nightly.20261104
#   curl -fsSL .../install.sh | sh -s -- --nightly
#
# Environment:
#   FUN_TAG       exact tag to install (overrides --nightly / latest)
#   FUN_DIR       install root (default: ~/.fun)
#   FUN_NO_PATH   set to 1 to skip the ~/.local/bin symlink
#   FUN_REPO      owner/repo (default: funlang/fun)
#   FUN_API_URL   API root (default: https://api.github.com/repos/$FUN_REPO)
#   FUN_BASE_URL  release download root (default: the GitHub release URL)
# ============================================================
set -eu

REPO="${FUN_REPO:-funlang/fun}"
ROOT="${FUN_DIR:-$HOME/.fun}"
API="${FUN_API_URL:-https://api.github.com/repos/$REPO}"
TAG="${FUN_TAG:-}"
EXPLICIT_TAG="$TAG"
CHANNEL=stable

usage() {
    cat <<EOF
usage: install.sh [--tag TAG] [--nightly] [--dir DIR] [--no-path]

  --tag TAG     install an exact tag (e.g. v9.5.4)
  --nightly     install the newest nightly prerelease
  --dir DIR     install root (default: ~/.fun)
  --no-path     do not create ~/.local/bin/fun
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --tag) TAG="${2:?--tag needs a value}"; shift 2 ;;
        --nightly) CHANNEL=nightly; shift ;;
        --dir) ROOT="${2:?--dir needs a value}"; shift 2 ;;
        --no-path) FUN_NO_PATH=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "install: '$1' is required" >&2
        exit 1
    }
}
need curl
need uname

os=$(uname -s)
case "$os" in
    Darwin) os=macos ;;
    Linux) os=linux ;;
    *) echo "install: unsupported OS: $os" >&2; exit 1 ;;
esac

case "$(uname -m)" in
    arm64|aarch64) arch=arm64 ;;
    x86_64|amd64) arch=x64 ;;
    *) echo "install: unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
platform="$os-$arch"

latest_tag() {
    curl -fsSL "$API/releases/latest" |
      sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

newest_nightly_tag() {
    curl -fsSL "$API/releases?per_page=30" |
      tr ',' '\n' | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' |
      grep -- '-nightly\.' | head -n 1
}

if [ -z "$TAG" ]; then
    if [ "$CHANNEL" = nightly ]; then
        TAG=$(newest_nightly_tag) || true
    else
        TAG=$(latest_tag) || true
    fi
fi
[ -n "$TAG" ] || { echo "install: could not determine a release tag; pass --tag" >&2; exit 1; }

case "$platform" in
    macos-*) ext=zip ;;
    *) ext=tar.gz ;;
esac
asset="fun-${TAG}-${platform}.${ext}"
base="${FUN_BASE_URL:-https://github.com/$REPO/releases/download/$TAG}"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/fun-install.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "install: downloading $asset"
if ! curl -fL --retry 3 -o "$tmp/$asset" "$base/$asset"; then
    if [ -n "$EXPLICIT_TAG" ] || [ "$CHANNEL" = nightly ]; then
        echo "install: no $platform asset for $TAG" >&2
        exit 1
    fi
    # The latest stable release may predate binary assets. Fall back to the
    # newest nightly rather than failing outright, and say so clearly.
    fallback=$(newest_nightly_tag) || true
    [ -n "$fallback" ] || { echo "install: no downloadable release found" >&2; exit 1; }
    echo "install: warning: stable $TAG has no $platform asset; using nightly $fallback"
    TAG="$fallback"
    asset="fun-${TAG}-${platform}.${ext}"
    base="${FUN_BASE_URL:-https://github.com/$REPO/releases/download/$TAG}"
    curl -fL --retry 3 -o "$tmp/$asset" "$base/$asset" || {
        echo "install: no $platform asset for $TAG" >&2; exit 1; }
fi
curl -fsSL --retry 3 -o "$tmp/SHA256SUMS" "$base/SHA256SUMS"

line=$(awk -v a="$asset" '$2 == a { print; exit }' "$tmp/SHA256SUMS")
[ -n "$line" ] || { echo "install: $asset is not listed in SHA256SUMS" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$tmp" && printf '%s\n' "$line" | sha256sum -c - )
else
    ( cd "$tmp" && printf '%s\n' "$line" | shasum -a 256 -c - )
fi

mkdir -p "$ROOT"
dest="$ROOT/$TAG"
rm -rf "$dest"
mkdir -p "$dest"
echo "install: extracting to $dest"
case "$ext" in
    zip)
        need unzip
        unzip -q "$tmp/$asset" -d "$tmp/x"
        ;;
    tar.gz)
        tar -xzf "$tmp/$asset" -C "$tmp"
        mkdir -p "$tmp/x"
        mv "$tmp/fun-${TAG}-${platform}" "$tmp/x/"
        ;;
esac

# The archive has a single top-level directory.
inner=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ -n "$inner" ] || { echo "install: unexpected archive layout" >&2; exit 1; }
(cd "$inner" && tar cf - .) | (cd "$dest" && tar xf -)
chmod +x "$dest/fun/fun" "$dest/fun/fun-safe" 2>/dev/null || true
# Compatibility links: older docs and scripts invoke funcmd and funcmd-safe.
ln -sfn fun "$dest/fun/funcmd"
ln -sfn fun-safe "$dest/fun/funcmd-safe"

# macOS: no code signing, so the only reliable path is to avoid/remove the
# quarantine attribute. curl downloads are not quarantined; this also handles
# an archive that was extracted by Finder.
if [ "$os" = macos ] && command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
fi

ln -sfn "$dest" "$ROOT/current"

if [ -z "${FUN_NO_PATH:-}" ]; then
    bin="$HOME/.local/bin"
    mkdir -p "$bin"
    ln -sfn "$dest/fun/fun" "$bin/fun"
    ln -sfn "$dest/fun/fun" "$bin/funcmd"
    case ":$PATH:" in
        *":$bin:"*) ;;
        *) echo "install: add $bin to PATH (or run $dest/fun/fun directly)" ;;
    esac
fi

echo "install: Fun $TAG -> $dest"
echo "install: run: $dest/fun/fun --help"
if [ "$os" = macos ]; then
    echo "install: unsigned build; quarantine was cleared for this directory"
fi
