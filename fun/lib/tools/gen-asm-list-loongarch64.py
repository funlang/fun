#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# gen-asm-list-loongarch64: build fun/lib/asm-list-loongarch64.fd from the
# LoongArch opcode table that ships with GNU binutils.
#
#   fun/lib/tools/gen-asm-list-loongarch64.py <binutils-src>/opcodes/loongarch-opc.c
#
# Why binutils and not a hand-written table: the opcode file already encodes
# every instruction's base word, operand order and bit-field placement, e.g.
#
#   { 0x02800000, 0xffc003e0, "addi.w", "r0:5,r5:5,s10:12", ... }
#
# where the format string means "GPR at bit 0 width 5, GPR at bit 5 width 5,
# signed immediate at bit 10 width 12". The generator only has to translate
# that notation into the slot grammar lib-asm-loongarch64.fun understands:
#
#   key   = "<mnemonic> <shape>,..."      e.g. addi.w r,r,#
#   value = "<8 hex base>|r0@0|r1@5|y2@10:12"
#
# Slots (the encoder is case-sensitive, so signed is 'y', not 'V', because
# Fun's string comparison is case-insensitive):
#   r<i>@b          GPR operand i at bit b (5 bits)
#   f<i>@b          FPR operand i at bit b (5 bits)
#   c<i>@b          FCC operand i at bit b (3 bits)
#   v<i>@b:w[:s]    unsigned immediate, w bits, >>s
#   y<i>@b:w[:s]    signed immediate, w bits, >>s
#
# Branch displacements ("sb") are not table slots: the encoder knows their
# split layout per mnemonic and resolves labels/fixups in a second pass. The
# table carries only the base word under both the "L" (label) and "#" (numeric
# byte offset) shapes.
#
# The generated file is checked in, so building Fun never needs binutils. Run
# the script only when refreshing the table against a new binutils release;
# fun/test/tools/asm-loongarch64-diff.sh then proves every entry byte-for-byte
# against GNU as.
#
# Sections deliberately skipped: privilege, LSX/LASX/LVZ/LBT (vector/extension
# state we do not model) and any entry whose format uses a vector register or a
# '+' bit-twiddling suffix.

import re
import sys

# Opcode sections we read. "4opt" holds the 4-operand scalar float
# instructions (fmadd/fmsub) and fcmp.*; the vector entries inside it are
# filtered out by the field check below.
WANTED_SECTIONS = {
    'fix', 'single_float', 'double_float', 'imm', 'load_store',
    'single_float_load_store', 'double_float_load_store',
    'float_jmp', 'jmp', '4opt_single_float', '4opt_double_float', 'alias',
}

# Macro/alias names we handle ourselves or that need relocations.
SKIP_NAMES = {
    'li.w', 'li.d', 'la', 'la.global', 'la.local', 'la.abs', 'la.pcrel',
    'la.tls.ie', 'la.tls.ld', 'la.tls.gd', 'bgt',
    'j', 'jal', 'call', 'pcaddi',
}

ENTRY_RE = re.compile(
    r'\{\s*(0x[0-9A-Fa-f]+|0)\s*,\s*(0x[0-9A-Fa-f]+|0)\s*,'
    r'\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,')
SECTION_RE = re.compile(r'static struct loongarch_opcode loongarch_(\w+)_opcodes\[\]')

# field type -> (shape letter, slot letters)
SCALAR_FIELD = re.compile(
    r'^(r|f|c)(\d+):(\d+)|'
    r'^(so|sb|s|u)(\d+):(\d+)(.*)$')


def parse_num(s):
    return int(s, 16) if s.lower().startswith('0x') else int(s)


def parse_format(fmt):
    """Return (shapes, slots, branch_specs) for one format string.

    branch_specs maps operand index -> {'parts': [(bit, width)], 'scale': n}.
    """
    shapes = []
    slots = []
    branch = {}
    if fmt.strip() == '':
        return shapes, slots, branch
    for i, f in enumerate(fmt.split(',')):
        f = f.strip()
        m = re.match(r'^(r|f|c)(\d+):(\d+)$', f)
        if m:
            kind, bit, width = m.group(1), int(m.group(2)), int(m.group(3))
            assert width in (3, 5), f
            shapes.append(kind)
            slots.append('%s%d@%d' % (kind, i, bit))
            continue
        m = re.match(r'^(so|sb|s|u)(\d+):(\d+)(.*)$', f)
        if m:
            kind, bit, width, tail = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
            if kind == 'sb':
                # "sb0:5|10:16<<2": split branch displacement.
                parts = [(bit, width)]
                rest = tail
                scale = 1
                sm = re.search(r'<<(\d+)', rest)
                if sm:
                    scale = 1 << int(sm.group(1))
                for pm in re.finditer(r'\|(\d+):(\d+)', rest):
                    parts.append((int(pm.group(1)), int(pm.group(2))))
                branch[i] = {'parts': parts, 'scale': scale,
                             'bits': sum(w for _, w in parts)}
                shapes.append('B')       # one operand; main() picks L or #
                continue
            scale = 1
            sm = re.search(r'<<(\d+)', tail)
            if sm:
                scale = 1 << int(sm.group(1))
            if '+1' in tail or kind in ('s', 'so'):
                if '+1' in tail:
                    raise ValueError('unsupported scaled field: ' + f)
                slot = 'y%d@%d:%d' % (i, bit, width)
            else:
                slot = 'v%d@%d:%d' % (i, bit, width)
            if scale > 1:
                shift = scale.bit_length() - 1
                slot += ':%d' % shift
            shapes.append('#')
            slots.append(slot)
            continue
        raise ValueError('unsupported field: ' + f)
    return shapes, slots, branch


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: gen-asm-list-loongarch64.py <loongarch-opc.c>')
    src = sys.argv[1]
    text = open(src, encoding='utf-8', errors='replace').read()

    section = None
    entries = {}   # key -> value
    order = []
    branch_shapes = {}  # mnemonic -> set of branch shapes seen
    for line in text.splitlines():
        sm = SECTION_RE.search(line)
        if sm:
            section = sm.group(1)
            continue
        if section not in WANTED_SECTIONS:
            continue
        m = ENTRY_RE.search(line)
        if not m:
            continue
        match, mask = parse_num(m.group(1)), parse_num(m.group(2))
        name, fmt = m.group(3), m.group(4)
        if match == 0 or name in SKIP_NAMES:
            continue
        if any(t in name for t in ('vfmadd', 'vfmsub', 'xvfmadd', 'xvfmsub')):
            continue
        try:
            shapes, slots, branch = parse_format(fmt)
        except ValueError:
            continue
        if any(s in ('v', 'x') for s in shapes):
            continue
        # A branch operand has two spellings for the same base word: a label
        # ("L", resolved by a fixup) and a numeric byte offset ("#").
        key_shapes = [shapes]
        if branch:
            idx = shapes.index('B')
            key_shapes = []
            for tag in ('L', '#'):
                alt = shapes[:]
                alt[idx] = tag
                key_shapes.append(alt)
        for sh in key_shapes:
            key = name + ((' ' + ','.join(sh)) if sh else '')
            val = '%08X' % match
            if slots:
                val += '|' + '|'.join(slots)
            if key in entries and entries[key] != val:
                raise SystemExit('duplicate key %r: %s vs %s' % (key, entries[key], val))
            if key not in entries:
                order.append(key)
                entries[key] = val

    out = []
    out.append('#!kvd:=')
    out.append('# asm-list-loongarch64.fd -- LoongArch64 instruction templates for')
    out.append('# lib-asm-loongarch64.fun. GENERATED by')
    out.append('#   fun/lib/tools/gen-asm-list-loongarch64.py <binutils>/opcodes/loongarch-opc.c')
    out.append('# from GNU binutils (verified against 2.41). Do not hand-edit; refresh')
    out.append('# with the script and re-run fun/test/tools/asm-loongarch64-diff.sh.')
    out.append('#')
    out.append('# key   = "<mnemonic> <op-shape>,..."   e.g. addi.w r,r,#')
    out.append('# value = "<8 hex base>|<slot>..."      e.g. 02800000|r0@0|r1@5|y2@10:12')
    out.append('#')
    out.append('# Slots: r/f/c = GPR/FPR/FCC at bit; v = unsigned imm; y = signed imm;')
    out.append('# optional ":w" is the field width and ":s" scales the value by 2^s.')
    out.append('# Branch displacements are resolved by the encoder, not by slots.')
    out.append('#')
    out.append('# After editing, rebuild the packed form with:')
    out.append('#   src/prj/fun/funcmd fun/lib/tools/make-asm-list.fun \\')
    out.append('#       fun/lib/asm-list-loongarch64.fd')
    for key in sorted(order):
        out.append('%s="%s"' % (key, entries[key]))
    sys.stdout.write('\n'.join(out) + '\n')


if __name__ == '__main__':
    main()
