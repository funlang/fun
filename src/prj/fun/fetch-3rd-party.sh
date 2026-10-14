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
        curl -fSL --retry 3 -o "$out" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out" "$url"
    else
        echo "need curl or wget to download $url" >&2
        exit 1
    fi
}

# install_dir <target-name> <url> <archive-name>
install_dir() {
    target="$1"; url="$2"; archive="$3"
    dest="$THIRD/$target"
    if [ -d "$dest" ] && [ "$force" -ne 1 ]; then
        echo "kept    src/3rd/$target (already present; use --force to re-fetch)"
        return 0
    fi
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/fun-3rd-XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT INT TERM
    echo "fetch   $url"
    fetch "$url" "$tmp/$archive"
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
    install_dir pcre-8 "$PCRE_URL" pcre-8.45.tar.gz
fi
if [ "$want_tcc" -eq 1 ]; then
    install_dir tcc "$TCC_URL" tcc-0.9.27.tar.bz2
fi

echo "third-party sources ready under src/3rd/"
