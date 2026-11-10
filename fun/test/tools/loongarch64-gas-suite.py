#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# loongarch64-gas-suite: run binutils' own LoongArch gas testsuite without
# DejaGnu, to validate the assembler used as the encoding oracle.
#
#   python3 fun/test/tools/loongarch64-gas-suite.py <binutils>/gas/testsuite/gas/loongarch
#
# asm-loongarch64-diff.sh trusts `loongarch64-linux-gnu-as`. This script checks
# that trust: it assembles each upstream X.s, disassembles the object, and
# compares the instruction words with the expected words in X.d. It is a
# reduced runner (no DejaGnu): it honours #as:/#objdump:/#skip: directives, but
# skips tests that need #as options this runner does not model, error tests
# (.l), and tests with no instruction words (data/relocation-only).
#
# AS/OBJDUMP default to $LA_AS/$LA_OBJDUMP, then loongarch64-linux-gnu-*.
# Exit code is non-zero on any mismatch.

import fnmatch
import os
import re
import subprocess
import sys
import tempfile

TARGET = 'loongarch64-unknown-linux-gnu'
KNOWN_AS_OPTS = {'-mla64', '-mabi=lp64d'}

def directives(path):
    d = {'as': '', 'objdump': '-d', 'skip': '', 'notarget': ''}
    for line in open(path, encoding='utf-8', errors='replace'):
        m = re.match(r'^#(as|objdump|skip|notarget):\s*(.*)$', line.strip())
        if m:
            d[m.group(1)] = m.group(2)
    return d


def instr_words(text):
    out = []
    for line in text.splitlines():
        # actual objdump line: "   0:\t03400000 \tnop"
        m = re.match(r'^\s*[0-9a-fA-F]+:\s+([0-9a-fA-F]{8})\b', line)
        if not m:
            # expected .d line: "[ \t]+0:[ \t]+03400000[ \t]+nop"
            m = re.search(r':\s*(?:\[\s*[^\]]*\]\s*[*+]?\s*)?([0-9a-fA-F]{8})\b', line)
        if m:
            out.append(m.group(1).lower())
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: loongarch64-gas-suite.py <binutils-src/gas/testsuite/gas/loongarch>')
    suite = sys.argv[1]
    as_bin = os.environ.get('LA_AS', 'loongarch64-linux-gnu-as')
    od_bin = os.environ.get('LA_OBJDUMP', 'loongarch64-linux-gnu-objdump')
    if not (os.access(as_bin, os.X_OK) or shutil_which(as_bin)):
        sys.exit('assembler not found: ' + as_bin)
    if not (os.access(od_bin, os.X_OK) or shutil_which(od_bin)):
        sys.exit('objdump not found: ' + od_bin)

    tmp = tempfile.mkdtemp(prefix='la-gas-suite-')
    npass = nfail = nskip = nother = 0
    fails = []
    for s in sorted(f for f in os.listdir(suite) if f.endswith('.s')):
        base = s[:-2]
        dpath = os.path.join(suite, base + '.d')
        if not os.path.exists(dpath):
            continue
        d = directives(dpath)
        if d['skip'] and fnmatch.fnmatch(TARGET, d['skip']):
            nskip += 1
            continue
        if d['notarget'] and not fnmatch.fnmatch(TARGET, d['notarget']):
            nskip += 1
            continue
        asopts = d['as'].split()
        if any(o.startswith('-m') and o not in KNOWN_AS_OPTS for o in asopts):
            nskip += 1
            continue
        obj = os.path.join(tmp, base + '.o')
        p = subprocess.run([as_bin, '-o', obj] + asopts + [os.path.join(suite, s)],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        if p.returncode != 0:
            # X.l marks an intentional assembler-error test
            if os.path.exists(os.path.join(suite, base + '.l')):
                nother += 1
            else:
                nfail += 1
                fails.append((base, 'AS-FAIL', (p.stderr or '').strip().splitlines()[:1]))
            continue
        odopts = d['objdump'].split() or ['-d']
        q = subprocess.run([od_bin] + odopts + [obj],
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        got = instr_words(q.stdout)
        want = instr_words(open(dpath, encoding='utf-8', errors='replace').read())
        if not want:
            nother += 1
            continue
        if got == want:
            npass += 1
        else:
            k = 0
            while k < len(got) and k < len(want) and got[k] == want[k]:
                k += 1
            g = got[k] if k < len(got) else 'EOF'
            w = want[k] if k < len(want) else 'EOF'
            nfail += 1
            fails.append((base, 'MISMATCH', 'word %d: got %s want %s' % (k, g, w)))
    for name, kind, detail in fails:
        print('%-28s %-10s %s' % (name, kind, detail))
    print('gas-suite: %d pass, %d fail, %d skip, %d other'
          % (npass, nfail, nskip, nother))
    return 1 if nfail else 0


def shutil_which(cmd):
    for p in os.environ.get('PATH', '').split(os.pathsep):
        c = os.path.join(p, cmd)
        if os.access(c, os.X_OK):
            return c
    return None


if __name__ == '__main__':
    sys.exit(main())
