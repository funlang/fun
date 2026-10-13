#!/bin/sh
# Which stdlib modules can be `use`d on this host?
#
# Many modules are Windows-only by design (they bind kernel32/user32/zlib.dll/
# COM), so a FAIL here is expected for them - see art/notes/roadmap-compatibility.md
# for the ported/not-ported split. This script exists to measure the Linux port's
# progress and to catch accidental load regressions in ported modules.
#
# Platform split convention: a Windows implementation keeps the plain module
# name (so existing code is untouched) and the Unix one is <name>-unx.fun. The
# old Linux name <name>-lnx.fun is kept as a thin wrapper (it just `use`s the
# -unx file), so on Linux either name loads the same code.
#
# Usage: fun/test/lib-loadcheck.sh   (from the repo root)
cd "$(dirname "$0")/../.." || exit 2
ok=0; bad=0
for f in fun/lib/*.fun; do
  n=$(basename "$f" .fun)
  # skip backend units: <name>-unx / <name>-lnx are the Unix implementation and
  # its Linux alias, and lib-unicode-base / lib-winsock-base are the shared
  # bases of a Windows/Unix split -- neither is a standalone stdlib module.
  # (lib-base *is* a module.)
  case "$n" in *-lnx|*-unx|lib-unicode-base|lib-winsock-base) continue;; esac
  t="$f"
  if [ -f "fun/lib/${n}-unx.fun" ]; then t="fun/lib/${n}-unx.fun"; fi
  if [ -f "fun/lib/${n}-lnx.fun" ]; then t="fun/lib/${n}-lnx.fun"; fi
  printf "use '%s';\n?. 'loaded';\n" "$t" > fun/test/.loadcheck-one.fun
  out=$(src/prj/fun/funcmd fun/test/.loadcheck-one.fun 2>&1 | tr -d '\r')
  if printf '%s' "$out" | grep -q '^loaded$'; then
    ok=$((ok+1)); printf 'LOAD  %s\n' "$n"
  else
    bad=$((bad+1))
    reason=$(printf '%s' "$out" | grep -m1 -iE 'error|not found|cannot load|violation' | cut -c1-60)
    printf 'FAIL  %-22s %s\n' "$n" "$reason"
  fi
done
rm -f fun/test/.loadcheck-one.fun
printf '\nloaded=%s failed=%s\n' "$ok" "$bad"
