#!/bin/sh
# ============================================================
# Fun - fetch the third-party C sources the interpreter build compiles.
#
# The repo does not carry these (see .gitignore and README "Third-party
# dependencies"), but the Linux/macOS build scripts compile them when present:
#
#   src/3rd/pcre-8/   PCRE 8.45   -> regex (-dRegex)
#   src/3rd/tcc/      TCC 0.9.27  -> libtcc.so, runtime C compile (lib-tcc.fun)
#
# A missing dependency only degrades the build, so this script is a convenience
# for developers and CI; it is safe to re-run (an existing directory is left
# alone unless --force is given).
#
# Usage:
#   src/prj/fun/fetch-3rd-party.sh              # fetch what is missing
#   src/prj/fun/fetch-3rd-party.sh --force      # re-fetch even if present
#   src/prj/fun/fetch-3rd-party.sh --pcre-only
#   src/prj/fun/fetch-3rd-party.sh --tcc-only
#
# Needs curl or wget, tar (with gzip/bzip2 support), and network access.
# ============================================================
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
THIRD="$(cd "$HERE/../../.." && pwd)/src/3rd"

PCRE_URL="https://downloads.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.gz"
TCC_URL="https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27.tar.bz2"
# Pinned SHA256 of the upstream release archives. A mirror that serves a
# different file (or a truncated/HTML error page) must not become a build
# input: the release pipeline ships interned binaries, not just source.
PCRE_SHA256="4e6ce03e0336e8b4a3d6c2b70b1c5e18590a5673a98186da90d4f33c23defc09"
TCC_SHA256="de23af78fca90ce32dff2dd45b3432b2334740bb9bb7b05bf60fdbfc396ceb9c"

force=0
want_pcre=1
want_tcc=1
for a in "$@"; do
    case "$a" in
        --force)     force=1 ;;
        --pcre-only) want_tcc=0 ;;
        --tcc-only)  want_pcre=0 ;;
        *) echo "usage: $0 [--force|--pcre-only|--tcc-only]" >&2; exit 2 ;;
    esac
done

fetch() {
    url="$1"; out="$2"
    if command -v curl >/dev/null 2>&1; then
        # --retry-all-errors also covers DNS/connect failures, which plain
        # --retry does not; runners occasionally lose name resolution.
        curl -fSL --retry 5 --retry-all-errors --retry-delay 5 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget --tries=5 --waitretry=5 -O "$out" "$url"
    else
        echo "need curl or wget to download $url" >&2
        exit 1
    fi
}

# check_sha256 <file> <expected> <label>
check_sha256() {
    file="$1"; expected="$2"; label="$3"
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        echo "warning: no sha256sum/shasum; cannot verify $label" >&2
        return 0
    fi
    if [ "$actual" != "$expected" ]; then
        echo "error: SHA256 mismatch for $label" >&2
        echo "  expected $expected" >&2
        echo "  actual   $actual" >&2
        return 1
    fi
    echo "sha256  $label ok"
}

# install_dir <target-name> <url> <archive-name> <sha256>
install_dir() {
    target="$1"; url="$2"; archive="$3"; sha256="$4"
    dest="$THIRD/$target"
    if [ -d "$dest" ] && [ "$force" -ne 1 ]; then
        echo "kept    src/3rd/$target (already present; use --force to re-fetch)"
        return 0
    fi
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/fun-3rd-XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    echo "fetch   $url"
    fetch "$url" "$tmp/$archive"
    check_sha256 "$tmp/$archive" "$sha256" "$archive" || { rm -rf "$tmp"; exit 1; }
    echo "extract $archive"
    tar -xf "$tmp/$archive" -C "$tmp"
    # the tarball unpacks into a single top-level dir; use it as the target
    src="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
    [ -n "$src" ] || { echo "unexpected archive layout for $archive" >&2; exit 1; }
    rm -rf "$dest"
    mkdir -p "$THIRD"
    mv "$src" "$dest"
    rm -rf "$tmp"
    trap - EXIT INT TERM
    echo "done    src/3rd/$target"
}

mkdir -p "$THIRD"

if [ "$want_pcre" -eq 1 ]; then
    install_dir pcre-8 "$PCRE_URL" pcre-8.45.tar.gz "$PCRE_SHA256"
fi
if [ "$want_tcc" -eq 1 ]; then
    install_dir tcc "$TCC_URL" tcc-0.9.27.tar.bz2 "$TCC_SHA256"
fi

echo "third-party sources ready under src/3rd/"
