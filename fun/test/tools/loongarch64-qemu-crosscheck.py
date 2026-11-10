#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# loongarch64-qemu-crosscheck: verify our instruction table and encoder against
# QEMU's independent LoongArch decoder.
#
#   curl -O https://raw.githubusercontent.com/qemu/qemu/v8.2.0/target/loongarch/insns.decode
#   python3 fun/test/tools/loongarch64-qemu-crosscheck.py insns.decode
#   python3 fun/test/tools/loongarch64-qemu-crosscheck.py --fun ./fun/funcmd insns.decode
#
# Why this exists: asm-list-loongarch64.fd and the GNU assembler both come from
# binutils' opcodes/loongarch-opc.c, so asm-loongarch64-diff.sh alone cannot
# catch an error that is present in that source table. QEMU carries a separate
# decode table written from the LoongArch manual, which makes it a genuinely
# independent oracle.
#
# Two checks:
#   1. table metadata: base word and bit-field placement for every entry the
#      two tables share.
#   2. --fun: generate a concrete instruction for each shared entry, compute
#      the expected word from QEMU's fields, run the Fun encoder over them, and
#      compare. This validates the encoder itself with no binutils in the loop.
#
# The comparison ignores textual operand order: QEMU and gas name the two
# source operands of the atomic am* instructions in opposite order (bit
# positions agree). Those are excluded from check 2 because the *textual*
# spelling differs; gas compatibility is covered by asm-loongarch64-diff.sh.
#
# Exit code is non-zero on any mismatch.

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
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
    toks, args, _ = formats[fmt]
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


def operand_value(arg, i):
    if arg in ('rd', 'rj', 'rk'):
        return 'r', (i % 20) + 4
    if arg in ('fd', 'fj', 'fk', 'fa'):
        return 'f', (i % 28) + 1
    if arg in ('cd', 'cj', 'ca'):
        return 'c', 0
    if arg == 'imm':
        return '#', 0
    return None, None


def main():
    argv = sys.argv[1:]
    funcmd = None
    if '--fun' in argv:
        k = argv.index('--fun')
        funcmd = argv[k + 1]
        del argv[k:k + 2]
    if not argv:
        sys.exit('usage: loongarch64-qemu-crosscheck.py [--fun FUNCMD] '
                 '<insns.decode> [table.fd]')
    qpath = argv[0]
    fdpath = argv[1] if len(argv) > 1 else DEFAULT_FD
    formats = load_formats(qpath)
    table = load_table(fdpath)

    checked = mismatch = skipped = 0
    cases = []  # (asm line, expected word) for --fun
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
        encode_ok = not mn.startswith('am')
        unsupported = False
        for i, an in enumerate(args):
            kind, val = operand_value(an, i)
            if kind is None:
                unsupported = True
                break
            if kind == 'c':
                # fcc fields use a 3-bit field, not the default 5
                pos, wid, _ = fields[an]
                shape.append('c')
                slots.append('c%d@%d' % (i, pos))
            elif kind == '#':
                if 'imm' not in fields:
                    unsupported = True
                    break
                pos, wid, signed = fields['imm']
                shape.append('#')
                slots.append('%s%d@%d:%d' % ('y' if signed else 'v', i, pos, wid))
            else:
                pos = fields[an][0]
                # fp args use 'f', integer args 'r'
                shape.append(kind)
                slots.append('%s%d@%d' % (kind, i, pos))
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
            continue
        if encode_ok:
            text = [mn]
            exp = want_base
            for i, an in enumerate(args):
                kind, val = operand_value(an, i)
                if kind == 'r':
                    text.append('$r%d' % val)
                elif kind == 'f':
                    text.append('$f%d' % val)
                elif kind == 'c':
                    text.append('$fcc0')
                else:
                    text.append('0')
                pos, wid, _ = fields.get(an, (0, 5, False))
                exp |= (val & ((1 << wid) - 1)) << pos
            cases.append((', '.join([text[0]]) + ' ' + ', '.join(text[1:])
                          if len(text) > 1 else text[0], exp))

    print('qemu-crosscheck: %d checked, %d mismatches, %d skipped'
          % (checked, mismatch, skipped))

    if funcmd:
        with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as f:
            for text, _ in cases:
                f.write(text + '\n')
            cpath = f.name
        try:
            p = subprocess.run([funcmd, 'fun/test/tools/loongarch64-encode.fun', cpath],
                               cwd=REPO, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, universal_newlines=True,
                               env=dict(os.environ, LC_ALL='C'))
        finally:
            os.unlink(cpath)
        if p.returncode != 0:
            print('qemu-encode: funcmd failed: ' + (p.stderr or '').strip())
            return 1
        got = []
        for line in p.stdout.splitlines():
            if '\t' not in line:
                continue
            _, hx = line.split('\t', 1)
            hx = hx.strip().upper()
            words = []
            for i in range(0, len(hx), 8):
                c = hx[i:i + 8]
                words.append(int(c[6:8] + c[4:6] + c[2:4] + c[0:2], 16))
            got.append(words)
        enc_bad = 0
        for i, (text, exp) in enumerate(cases):
            g = got[i] if i < len(got) else []
            if g != [exp]:
                if enc_bad < 10:
                    print('ENCODE %s qemu=%08X fun=%s'
                          % (text, exp, ' '.join('%08X' % w for w in g)))
                enc_bad += 1
        print('qemu-encode: %d checked, %d mismatches' % (len(cases), enc_bad))
        mismatch += enc_bad

    return 1 if mismatch else 0


if __name__ == '__main__':
    sys.exit(main())
