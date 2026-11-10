#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# loongarch64-tablecases: emit concrete assembly lines for the entries in
# fun/lib/asm-list-loongarch64.fd, for an exhaustive differential run against
# GNU as.
#
#   python3 fun/test/tools/loongarch64-tablecases.py > /tmp/tablecases.txt
#   LA_AS=... LA_OBJDUMP=... sh fun/test/tools/asm-loongarch64-diff.sh /tmp/tablecases.txt
#
#   # randomized registers and non-zero immediates (repeatable per seed)
#   python3 fun/test/tools/loongarch64-tablecases.py --random 1 > /tmp/var1.txt
#
# The checked-in loongarch64-cases.txt is the curated set (immediate
# boundaries, every branch split, li expansions). This script is the breadth
# check: every table key must be reachable and encode identically.
#
# Default mode uses distinct registers and immediate 0 (always in range and a
# multiple of every scale). --random SEED uses random register numbers, a
# non-zero in-range immediate (1 << scale), and "#4" for numeric branches, so
# non-zero slot values land at every bit position. AMO operands are chosen
# mutually distinct because gas rejects rd aliasing base or rt.
#
# Keys whose branch operand is spelled "L" are skipped: a label needs a second
# pass, which the curated test covers. The matching "#" key is emitted.

import os
import random
import re
import sys

BRANCH = {
    'b', 'bl', 'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu',
    'beqz', 'bnez', 'bceqz', 'bcnez', 'bltz', 'bgtz', 'bgez', 'blez',
}


def main():
    argv = sys.argv[1:]
    seed = None
    if '--random' in argv:
        k = argv.index('--random')
        if k + 1 >= len(argv):
            sys.exit('usage: loongarch64-tablecases.py [--random SEED]')
        seed = int(argv[k + 1])
        del argv[k:k + 2]
    if argv:
        sys.exit('usage: loongarch64-tablecases.py [--random SEED]')
    rnd = random.Random(seed) if seed is not None else None

    here = os.path.dirname(os.path.abspath(__file__))
    fd = os.path.normpath(os.path.join(here, '..', '..', 'lib',
                                       'asm-list-loongarch64.fd'))
    for line in open(fd, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^(.+?)="(.*)"$', line)
        if not m:
            continue
        key, value = m.group(1), m.group(2)
        mn, _, rest = key.partition(' ')
        parts = rest.split(',') if rest else []
        if 'L' in parts:
            continue
        scale = {}
        for sl in value.split('|')[1:]:
            sm = re.match(r'^[vy](\d+)@\d+:\d+(?::(\d+))?$', sl)
            if sm:
                scale[int(sm.group(1))] = int(sm.group(2) or 0)
        regs = None
        if rnd and mn.startswith('am') and parts == ['r', 'r', 'r']:
            regs = rnd.sample(range(32), 3)
        ops = []
        for i, sh in enumerate(parts):
            if sh == 'r':
                ops.append('$r%d' % (regs[i] if regs else
                                     (rnd.randint(0, 31) if rnd else (i % 20) + 4)))
            elif sh == 'f':
                ops.append('$f%d' % (rnd.randint(0, 31) if rnd else (i % 28) + 1))
            elif sh == 'c':
                ops.append('$fcc%d' % (rnd.randint(0, 7) if rnd else 0))
            elif sh == '#':
                if mn in BRANCH:
                    ops.append('#4' if rnd else '#0')
                else:
                    ops.append(str((1 << scale.get(i, 0)) if rnd else 0))
            else:
                raise SystemExit('%s: unsupported shape %r' % (key, sh))
        sys.stdout.write(mn + (' ' + ', '.join(ops) if ops else '') + '\n')


if __name__ == '__main__':
    main()
