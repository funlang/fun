#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# loongarch64-tablecases: emit one concrete assembly line per entry in
# fun/lib/asm-list-loongarch64.fd, for an exhaustive differential run against
# GNU as.
#
#   python3 fun/test/tools/loongarch64-tablecases.py > /tmp/tablecases.txt
#   LA_AS=... LA_OBJDUMP=... sh fun/test/tools/asm-loongarch64-diff.sh /tmp/tablecases.txt
#
# The checked-in loongarch64-cases.txt is the curated set (immediate
# boundaries, every branch split, li expansions). This script is the breadth
# check: every table key must be reachable and encode identically.
#
# Register operands get distinct numbers so slot positions are exercised.
# Immediate operands are 0 (always in range and a multiple of every scale);
# branch numeric offsets use "#0" so the diff script rewrites them to gas's
# PC-relative syntax.
#
# Keys whose branch operand is spelled "L" are skipped: a label needs a second
# pass, which the curated test covers. The matching "#" key is emitted.

import os
import re
import sys

BRANCH = {
    'b', 'bl', 'beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu',
    'beqz', 'bnez', 'bceqz', 'bcnez', 'bltz', 'bgtz', 'bgez', 'blez',
}


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    fd = os.path.join(here, '..', '..', 'lib', 'asm-list-loongarch64.fd')
    fd = os.path.normpath(fd)
    for line in open(fd, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^(.+?)="(.*)"$', line)
        if not m:
            continue
        key = m.group(1)
        mn, _, rest = key.partition(' ')
        parts = rest.split(',') if rest else []
        if 'L' in parts:
            continue
        ops = []
        for i, sh in enumerate(parts):
            if sh == 'r':
                ops.append('$r%d' % ((i % 20) + 4))
            elif sh == 'f':
                ops.append('$f%d' % ((i % 28) + 1))
            elif sh == 'c':
                ops.append('$fcc0')
            elif sh == '#':
                ops.append('#0' if mn in BRANCH else '0')
            else:
                raise SystemExit('%s: unsupported shape %r' % (key, sh))
        sys.stdout.write(mn + (' ' + ', '.join(ops) if ops else '') + '\n')


if __name__ == '__main__':
    main()
