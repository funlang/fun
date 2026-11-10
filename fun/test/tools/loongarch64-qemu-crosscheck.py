#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# loongarch64-qemu-crosscheck: verify our instruction table against QEMU's
# independent LoongArch decoder.
#
#   curl -O https://raw.githubusercontent.com/qemu/qemu/v8.2.0/target/loongarch/insns.decode
#   python3 fun/test/tools/loongarch64-qemu-crosscheck.py insns.decode
#
# Why this exists: asm-list-loongarch64.fd and the GNU assembler both come from
# binutils' opcodes/loongarch-opc.c, so asm-loongarch64-diff.sh alone cannot
# catch an error that is present in that source table. QEMU carries a separate
# decode table written from the LoongArch manual, which makes it a genuinely
# independent oracle for the base word and bit-field placement.
#
# The comparison ignores textual operand order: QEMU and gas name the two
# source operands of the atomic am* instructions in opposite order (the encoded
# bit positions agree, which is what matters here; gas compatibility is covered
# by asm-loongarch64-diff.sh). Immediates are compared by position, width,
# signedness and scale.
#
# Exit code is non-zero on any mismatch, so it can be used in a release check
# when a QEMU tree is available.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_FD = os.path.normpath(os.path.join(HERE, '..', '..', 'lib',
                                           'asm-list-loongarch64.fd'))


def load_formats(path):
    argsets = {}
    formats = {}
    for line in open(path, encoding='utf-8'):
        line = line.split('#')[0].strip()
        if not line:
            continue
        if line.startswith('&') and not line.startswith('&empty'):
            parts = line.split()
            argsets[parts[0][1:]] = parts[1:]
        elif line.startswith('@'):
            parts = line.split()
            toks, argset, overrides = [], None, {}
            for p in parts[1:]:
                if p.startswith('&'):
                    argset = p[1:]
                elif '=' in p:
                    k, v = p.split('=', 1)
                    overrides[k] = v
                else:
                    toks.append(p)
            formats[parts[0][1:]] = (
                toks, argsets.get(argset, []) if argset else [], overrides)
    return formats


def parse_format(fmt, formats):
    toks, args, over = formats[fmt]
    bits, fields, offset = [], {}, 0
    for t in toks:
        if ':' in t:
            name, spec = t.split(':', 1)
            signed = spec.startswith('s')
            width = int(spec[1:] if signed else spec)
            fields[name] = (32 - offset - width, width, signed)
            bits.append('.' * width)
            offset += width
        else:
            bits.append(t)
            offset += len(t)
    b = ''.join(bits)
    if len(b) != 32:
        raise ValueError('bad format %s: %d bits' % (fmt, len(b)))
    return int(b.replace('.', '0'), 2), fields, args


def load_table(path):
    table = {}
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line or line.startswith('#'):
            continue
        m = re.match(r'^(.+?)="(.*)"$', line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        mn, _, rest = key.partition(' ')
        shapes = tuple(rest.split(',')) if rest else ()
        vp = val.split('|')
        table[(mn, shapes)] = (int(vp[0], 16), vp[1:])
    return table


def slot_key(sl):
    """Reduce a table slot to (kind, bit, width, shift), dropping the operand
    index so textual operand order does not matter."""
    m = re.match(r'^([rfcvy])(\d+)@(\d+)(?::(\d+))?(?::(\d+))?$', sl)
    if not m:
        return sl
    letter, _, pos, wid, sh = m.groups()
    kind = letter if letter in 'rfc' else ('s' if letter == 'y' else 'u')
    return (kind, int(pos), int(wid or 5), int(sh or 0))


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: loongarch64-qemu-crosscheck.py <insns.decode> [table.fd]')
    qpath = sys.argv[1]
    fdpath = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_FD
    formats = load_formats(qpath)
    table = load_table(fdpath)

    checked = mismatch = skipped = 0
    for line in open(qpath, encoding='utf-8'):
        line = line.split('#')[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 3 or not parts[-1].startswith('@'):
            continue
        mn = parts[0].replace('_', '.')
        pat = ''.join(parts[1:-1])
        if len(pat) != 32 or set(pat) - set('01.'):
            continue
        try:
            _, fields, args = parse_format(parts[-1][1:], formats)
        except (KeyError, ValueError):
            skipped += 1
            continue
        shape, slots = [], []
        unsupported = False
        for i, an in enumerate(args):
            if an in ('rd', 'rj', 'rk'):
                pos = fields[an][0]
                shape.append('r')
                slots.append('r%d@%d' % (i, pos))
            elif an in ('fd', 'fj', 'fk'):
                pos = fields[an][0]
                shape.append('f')
                slots.append('f%d@%d' % (i, pos))
            elif an in ('cd', 'cj'):
                pos = fields[an][0]
                shape.append('c')
                slots.append('c%d@%d' % (i, pos))
            elif an == 'imm':
                if 'imm' not in fields:
                    unsupported = True
                    break
                pos, wid, signed = fields['imm']
                shape.append('#')
                slots.append(('%s%d@%d:%d' % ('y' if signed else 'v', i, pos, wid)))
            else:
                # offs/fcond/hint/sa/ms/ls/csr/cop/... are not table slots
                unsupported = True
                break
        if unsupported:
            skipped += 1
            continue
        key = (mn, tuple(shape))
        if key not in table:
            skipped += 1
            continue
        want_base = int(pat.replace('.', '0'), 2)
        got_base, got_slots = table[key]
        checked += 1
        if got_base != want_base:
            print('BASE %s %s qemu=%08X table=%08X'
                  % (mn, ','.join(shape), want_base, got_base))
            mismatch += 1
            continue
        if set(map(slot_key, got_slots)) != set(map(slot_key, slots)):
            print('SLOT %s %s qemu=%s table=%s'
                  % (mn, ','.join(shape), sorted(map(slot_key, slots)),
                     sorted(map(slot_key, got_slots))))
            mismatch += 1
    print('qemu-crosscheck: %d checked, %d mismatches, %d skipped'
          % (checked, mismatch, skipped))
    return 1 if mismatch else 0


if __name__ == '__main__':
    sys.exit(main())
