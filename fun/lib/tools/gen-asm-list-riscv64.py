#!/usr/bin/env python3
# Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# gen-asm-list-riscv64: build fun/lib/asm-list-riscv64.fd from the RISC-V
# opcode tables that ship with GNU binutils.
#
#   fun/lib/tools/gen-asm-list-riscv64.py <binutils-src>
#
# <binutils-src> is the root of an unpacked binutils tree; the script reads
# opcodes/riscv-opc.c and include/opcode/riscv-opc.h. Every instruction's base
# word comes from the MATCH_* macro and its operand placement from the format
# string (d=rd, s=rs1, t=rs2, j=I-imm, o=load offset, q=store offset,
# p=branch offset, a=jal offset, u=upper immediate, >=shift amount,
# E=csr number, Z=csr zimm). That notation is translated into the slot grammar
# lib-asm-riscv64.fun understands:
#
#   key   = "<mnemonic> <shape>,..."   e.g. addi r,r,#
#   value = "<8 hex base>|<slot>..."   e.g. 01300000|r0@7|r1@15|y2@20:12
#
# Slots (the encoder compares case-sensitively, so signed is 'y', not 'V'):
#   r<i>@b          GPR operand i at bit b (5 bits)
#   v<i>@b:w[:s]    unsigned immediate, w bits, value >> s
#   y<i>@b:w[:s]    signed immediate, w bits, value >> s
#   m<i>@b:w[:s]    value >> s, masked to w bits (no range check: the low half
#                   of a split displacement)
#
# Operand shapes: r = GPR, # = immediate or the offset of a memory operand,
# L = label (branch/jump target). A load `ld a0, 8(sp)` is written as
# two operands in the key ("r,#,r"): the encoder expands `off(base)` into an
# offset and a base register.
#
# Branch and jump displacements are not table slots: the encoder knows the
# B-type and J-type split layouts and resolves labels in a second pass.
#
# Only the base integer classes are read: I, M (via Zmmul where binutils
# splits it), Zicsr, Zifencei and the A-extension halves. Compressed (C),
# floating point, vector and vendor extensions are skipped because the
# encoder has no register model for them.
#
# The generated file is checked in, so building Fun never needs binutils.
# Refresh it only when bumping binutils, then re-run
# fun/test/tools/asm-riscv64-diff.sh to prove every entry byte-for-byte
# against riscv64-linux-gnu-as.

import os
import re
import sys

CLASSES = {
    "INSN_CLASS_I",
    "INSN_CLASS_M",
    "INSN_CLASS_ZMMUL",
    "INSN_CLASS_ZICSR",
    "INSN_CLASS_ZIFENCEI",
}

# format string -> (shape list, slot list). Slot entries are
# (kind, operand index, pos) or (kind, operand index, pos, width[, shift]).
FORMATS = {
    "d,s,t": (["r", "r", "r"], [("r", 0, 7), ("r", 1, 15), ("r", 2, 20)]),
    "d,s,j": (["r", "r", "#"], [("r", 0, 7), ("r", 1, 15), ("y", 2, 20, 12)]),
    "d,u": (["r", "#"], [("r", 0, 7), ("v", 1, 12, 20)]),
    "d,o(s)": (["r", "#", "r"], [("r", 0, 7), ("y", 1, 20, 12), ("r", 2, 15)]),
    "t,q(s)": (["r", "#", "r"],
               [("r", 0, 20), ("m", 1, 25, 7, 5), ("m", 1, 7, 5, 0), ("r", 2, 15)]),
    "s,t,p": (["r", "r", "L"], [("r", 0, 15), ("r", 1, 20)]),
    "d,a": (["r", "L"], [("r", 0, 7)]),
    "d,s,>": (["r", "r", "#"], [("r", 0, 7), ("r", 1, 15), ("v", 2, 20, 6)]),
    # RV64 word shifts (sllw/srlw/sraw) take a 5-bit shift amount.
    "d,s,<": (["r", "r", "#"], [("r", 0, 7), ("r", 1, 15), ("v", 2, 20, 5)]),
    "d,E,s": (["r", "#", "r"], [("r", 0, 7), ("v", 1, 20, 12), ("r", 2, 15)]),
    "d,E,Z": (["r", "#", "#"], [("r", 0, 7), ("v", 1, 20, 12), ("v", 2, 15, 5)]),
    "s,t": (["r", "r"], [("r", 0, 15), ("r", 1, 20)]),
    "": ([], []),
}

ENTRY = re.compile(
    r'\{"([^"]+)",\s*(\d+),\s*(INSN_CLASS_[A-Z0-9_]+),\s*"([^"]*)",\s*'
    r'([A-Z0-9_|()\s]+?),\s*([A-Z0-9_|()\s]+?),\s*[^,]+,\s*([^}]*)\}')

DEFINE = re.compile(r'^#define\s+(MATCH_[A-Z0-9_]+|MASK_[A-Z0-9_]+)\s+(0x[0-9a-fA-F]+)$',
                    re.M)


def slot_text(slot):
    kind, idx, pos = slot[0], slot[1], slot[2]
    if len(slot) == 3:
        return "%s%d@%d" % (kind, idx, pos)
    width = slot[3]
    shift = slot[4] if len(slot) > 4 else 0
    if shift:
        return "%s%d@%d:%d:%d" % (kind, idx, pos, width, shift)
    return "%s%d@%d:%d" % (kind, idx, pos, width)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: gen-asm-list-riscv64.py <binutils-src>")
    root = sys.argv[1]
    opc = os.path.join(root, "opcodes", "riscv-opc.c")
    hdr = os.path.join(root, "include", "opcode", "riscv-opc.h")
    for path in (opc, hdr):
        if not os.path.exists(path):
            sys.exit("not found: %s" % path)

    defs = {name: int(value, 16) for name, value in DEFINE.findall(open(hdr).read())}
    src = open(opc).read()
    rows = [m for m in ENTRY.finditer(src)]

    table = {}
    skipped = 0
    for m in rows:
        mn, xlen, cls, fmt, match, mask, flags = m.groups()
        if cls not in CLASSES or xlen == "32":
            continue
        if "INSN_ALIAS" in flags or "INSN_MACRO" in flags:
            continue
        if fmt not in FORMATS:
            skipped += 1
            continue
        # The match field is usually a single constant, but `fence` spells it
        # as MATCH_FENCE|MASK_PRED|MASK_SUCC. Only single tokens have a usable
        # base word; the operand-carrying `fence` form is skipped anyway.
        base = match.strip()
        if base not in defs:
            skipped += 1
            continue
        shapes, slots = FORMATS[fmt]
        key = mn + (" " + ",".join(shapes) if shapes else "")
        if key in table:
            continue
        value = "%08X" % defs[base]
        for slot in slots:
            value += "|" + slot_text(slot)
        table[key] = value

    out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "asm-list-riscv64.fd")
    header = """#!kvd:=
# asm-list-riscv64.fd -- RISC-V 64 instruction templates for
# lib-asm-riscv64.fun. GENERATED by
#   fun/lib/tools/gen-asm-list-riscv64.py <binutils-src>
# from GNU binutils (verified against 2.44). Do not hand-edit; refresh
# with the script and re-run fun/test/tools/asm-riscv64-diff.sh.
#
# key   = "<mnemonic> <op-shape>,..."   e.g. addi r,r,#
# value = "<8 hex base>|<slot>..."      e.g. 01300000|r0@7|r1@15|y2@20:12
#
# Slots: r = GPR at bit; v = unsigned imm; y = signed imm; m = raw masked
# value (low half of a split displacement). Optional ":w" is the field width
# and ":s" scales the value by 2^s.
#
# A load/store key lists the memory operand as two entries ("r,#,r"), because
# `ld a0, 8(sp)` expands to an offset and a base register.
#
# After editing, rebuild the packed form with:
#   src/prj/fun/funcmd fun/lib/tools/make-asm-list.fun \\
#       fun/lib/asm-list-riscv64.fd
"""
    with open(out, "w") as f:
        f.write(header)
        for key in sorted(table):
            f.write('%s="%s"\n' % (key, table[key]))
    print("wrote %s: %d entries (%d unsupported formats skipped)"
          % (out, len(table), skipped))


if __name__ == "__main__":
    main()
