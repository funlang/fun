// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-asm-riscv64: the RISC-V 64 backend of the hand-written-assembly path,
// sibling of lib-asm-pro.fun (x86), lib-asm-a64.fun (AArch64) and
// lib-asm-loongarch64.fun.
//
// It shares the executable-memory plumbing, the `ret_hex` tail hook and the
// `<name>` callback resolver in lib-asm.fun; the encoder is per-architecture.
//
// Usage (the module deliberately does NOT grab the global `Assembly`; the
// script opts in, so `use`-ing several backends stays deterministic):
//
//   use 'lib-asm-riscv64.fun';
//   Assembly = AssemblyRiscv64;
//   var f = Assembly('i:i', `#!asm
//   addi a0, a0, 1
//   ret
//   `);
//   f.Load(); ?. f.Run(41);
//
// ABI: the RISC-V LP64 ELF convention. Integer arguments a0-a7 (x10-x17),
// result a0, return address ra (x1). A hand-written leaf function should only
// touch the argument registers, the temporaries t0-t6 (x5-x7, x28-x31) and
// the saved registers it restores; keep sp (x2) 16-byte aligned.
//
// Encoding model: fixed-width 32-bit instructions with bit-fields, so the
// table format is the "<base word>|<slot>..." model of a64/loongarch64, NOT
// x86's "append operand bytes". `asm-list-riscv64.fd` is generated from the
// GNU binutils opcode table by
//   fun/lib/tools/gen-asm-list-riscv64.py <binutils-src>
// and checked byte-for-byte against riscv64-linux-as by
//   fun/test/tools/asm-riscv64-diff.sh
//
// Slot grammar (signed is 'y', not 'V': Fun's string comparison is
// case-insensitive, so signed/unsigned need different letters):
//   r<i>@b          GPR operand i at bit b
//   v<i>@b:w[:s]    unsigned immediate, w bits, value >> s
//   y<i>@b:w[:s]    signed immediate, w bits, value >> s
//   m<i>@b:w[:s]    value >> s masked to w bits (low half of a split field)
//
// Operand shapes: r = GPR, # = immediate or the offset of a memory operand,
// L = label (branch/jump target). Memory operands use the gas spelling
// `ld a0, 8(sp)` and expand to an offset plus a base register, so the table
// key for a load is "r,#,r".
//
// Branch displacements: local labels are resolved in a second pass. The
// B-type layout is [12]@31 [10:5]@25 [4:1]@8 [11]@7 and the J-type layout is
// [20]@31 [10:1]@21 [11]@20 [19:12]@12. A numeric branch operand is a signed
// BYTE offset, as in the GNU assembler; labels are preferable unless you are
// hand-computing relative offsets.
//
// Not covered yet: compressed (C), floating point, vector and atomic
// extensions. `fence` with pred/succ sets is not in the table either; use
// `fence.i` where an instruction-cache barrier is meant.

use 'lib-asm.fun';
use 'lib-zlib.fun';
use 'lib-regex.fun';

var _rv_cpu = 'host'.arg().getJson(fd: true).cpu;

// ---------------------------------------------------------------- the table
var asms_rv = RvAsmsInit();
fun RvAsmsInit()
  if zlib then
    use ':asm-list-riscv64.fd2.gz' as gz;
    result = inflate(gz).getJson(fd: true, sse: true);
  else
    raise 'lib-asm-riscv64: zlib is required for the asm list';
  end if;
end fun;

// ------------------------------------------------------------- small helpers
fun _rv_trim(s)
  result = s.replace(/^\s++|\s++$/g, '');
end fun;

fun _rv_strip(line)
  result = _rv_trim(line.replace(/;.*$/, ''));
end fun;

// Split an operand list on commas that are not inside parentheses, so
// `ld a0, 8(sp)` keeps the memory operand whole.
fun _rv_ops(rest)
  var ops = new [];
  var cur = '';
  var depth = 0;
  for i = 0 to rest.length()-1 do
    var ch = rest.substr(i, 1);
    if ch = '(' then
      depth += 1;
      cur &= ch;
    elsif ch = ')' then
      depth -= 1;
      cur &= ch;
    elsif ch = ',' and depth = 0 then
      ops.@add(_rv_trim(cur));
      cur = '';
    else
      cur &= ch;
    end if;
  end do;
  if _rv_trim(cur) <> '' then ops.@add(_rv_trim(cur)); end if;
  result = ops;
end fun;

fun _rv_num(t)
  var s = t;
  if s.substr(0, 1) = '#' then s = s.substr(1); end if;
  result = s.toNum();
end fun;

// GPR ABI names (x0-x31), including the s0/fp alias.
var _RV_GPR = [ zero: 0, ra: 1, sp: 2, gp: 3, tp: 4,
                t0: 5, t1: 6, t2: 7, s0: 8, fp: 8, s1: 9,
                a0: 10, a1: 11, a2: 12, a3: 13, a4: 14, a5: 15, a6: 16, a7: 17,
                s2: 18, s3: 19, s4: 20, s5: 21, s6: 22, s7: 23, s8: 24,
                s9: 25, s10: 26, s11: 27, t3: 28, t4: 29, t5: 30, t6: 31 ];

fun _rv_gprnum(s)
  // 0 compares equal to nil in Fun, so the zero register is matched before
  // the map lookup instead of relying on a nil test after it.
  if s = 'zero' then return 0; end if;
  var m = s.match(/^x(\d++)$/);
  if m.@@() <> '' then
    var n = m.@(1).toNum();
    if n > 31 then return -1; end if;
    return n;
  end if;
  // `.[key]` forces a string-key lookup. Plain `_RV_GPR[s]` treats a numeric
  // string as a positional index, so "5" would return the sixth value.
  var v = _RV_GPR.[s];
  if v <> nil then return v; end if;
  result = -1;
end fun;

fun _rv_operand(typ, num, text, shape)
  var r = new [];
  r.typ = typ; r.num = num; r.text = text; r.shape = shape;
  result = r;
end fun;

// One source operand -> one or two classified operands (`off(base)` becomes
// the offset and the base register).
fun _rv_class(t, out)
  var s = _rv_trim(t);
  if s.substr(0, 1) = '$' then s = s.substr(1); end if;
  var mem = s.match(/^(.*?)\(([^()]*)\)$/);
  if mem.@@() <> '' then
    var off = _rv_trim(mem.@(1));
    var base = _rv_trim(mem.@(2));
    var nb = _rv_gprnum(base.lower());
    if nb < 0 then raise 'bad base register in memory operand: $t'.eval(); end if;
    var n = 0;
    if off <> '' then
      if off.match(/^#?(-?(?:0x[0-9A-Fa-f]++|\d++))$/).@@() = '' then
        raise 'bad memory offset: $off'.eval();
      end if;
      n = _rv_num(off);
    end if;
    out.@add(_rv_operand('#', n, off, '#'));
    out.@add(_rv_operand('r', nb, base, 'r'));
    return;
  end if;
  var ng = _rv_gprnum(s.lower());
  if ng >= 0 then
    out.@add(_rv_operand('r', ng, t, 'r'));
    return;
  end if;
  if s.match(/^#?(-?(?:0x[0-9A-Fa-f]++|\d++))$/).@@() <> '' then
    out.@add(_rv_operand('#', _rv_num(s), t, '#'));
    return;
  end if;
  out.@add(_rv_operand('lbl', 0, s, 'L'));
end fun;

// ------------------------------------------------------- slot -> word patcher
fun _rv_slot(w, slot, ops)
  var m = slot.match(/^([rvym])(\d++)@(\d++)(?::(\d++))?(?::(\d++))?$/);
  if m.@@() = '' then raise 'bad slot: $slot'.eval(); end if;
  var op  = m.@(1);
  var i   = m.@(2).toNum();
  var pos = m.@(3).toNum();
  var wid = 5;
  if m.@(4) <> nil then wid = m.@(4).toNum(); end if;
  var sh = 0;
  if m.@(5) <> nil then sh = m.@(5).toNum(); end if;
  var o = ops[i];
  if o.typ = 'lbl' then
    raise 'label cannot be encoded in this operand position: $o.text'.eval();
  end if;
  var val = o.num;
  if op = 'r' then
    val = o.num;
  else
    if sh > 0 then
      // Arithmetic shift keeps the sign of negative displacements; the width
      // mask below drops the low bits that another slot already carries.
      val = val >> sh;
      if op <> 'm' and (o.num mod (1 << sh)) <> 0 then
        raise 'immediate not a multiple of $((1 << sh))'.eval();
      end if;
    end if;
    var mask0 = (1 << wid) - 1;
    if op = 'y' then
      if val < (0 - (1 << (wid-1))) or val > ((1 << (wid-1)) - 1) then
        raise 'signed immediate out of range: $slot'.eval();
      end if;
    elsif op = 'v' then
      if val < 0 or val > mask0 then
        raise 'immediate out of range: $slot'.eval();
      end if;
    end if;
  end if;
  var mask = (1 << wid) - 1;
  result = w bit or ((val bit and mask) << pos);
end fun;

fun _rv_emit(words, w)
  words.@add(w bit and 0xFFFFFFFF);
end fun;

// ------------------------------------------------------------ branch fixups
// Byte displacement patched into the B-type or J-type layout (bit 0 of the
// encoded field is always zero). Parts are listed most-significant first.
fun _rv_branch_info(mn)
  if mn = 'beq' or mn = 'bne' or mn = 'blt' or mn = 'bge' or mn = 'bltu'
     or mn = 'bgeu' then
    return [ parts: [[31,1],[7,1],[25,6],[8,4]], bits: 13 ];
  end if;
  if mn = 'jal' then
    return [ parts: [[31,1],[12,8],[20,1],[21,10]], bits: 21 ];
  end if;
  result = nil;
end fun;

fun _rv_patch_branch(w, bi, d)
  var total = bi.bits;
  var half = 1 << (total - 1);
  if d >= half or d < (0 - half) then
    raise 'branch out of range: $d'.eval();
  end if;
  var v = d bit and ((1 << total) - 1);
  var cum = 0;
  for part in bi.parts do
    var pos = part[0];
    var wid = part[1];
    var shift = total - cum - wid;
    w = w bit or (((v >> shift) bit and ((1 << wid) - 1)) << pos);
    cum += wid;
  end do;
  result = w;
end fun;

// ------------------------------------------------------------ line encoder
// Pseudo-instructions gas also accepts but which have no opcode-table entry.
fun _rv_pseudo(mn, ops)
  var r = new [];
  if mn = 'nop' then
    r.@add(_rv_operand('r', 0, 'zero', 'r'));
    r.@add(_rv_operand('r', 0, 'zero', 'r'));
    r.@add(_rv_operand('#', 0, '0', '#'));
    return [ mn: 'addi', ops: r ];
  end if;
  if mn = 'mv' and ops.@count() = 2 then
    r.@add(ops[0]); r.@add(ops[1]); r.@add(_rv_operand('#', 0, '0', '#'));
    return [ mn: 'addi', ops: r ];
  end if;
  if mn = 'ret' then
    r.@add(_rv_operand('r', 0, 'zero', 'r'));
    r.@add(_rv_operand('#', 0, '0', '#'));
    r.@add(_rv_operand('r', 1, 'ra', 'r'));
    return [ mn: 'jalr', ops: r ];
  end if;
  // `jal target` and `jalr rs` default rd to ra, like gas.
  if mn = 'jal' and ops.@count() = 1 then
    r.@add(_rv_operand('r', 1, 'ra', 'r'));
    r.@add(ops[0]);
    return [ mn: 'jal', ops: r ];
  end if;
  if mn = 'jalr' and ops.@count() = 2 and ops[1].typ = 'r' then
    // `jalr rd, rs` is the no-offset shorthand for `jalr rd, 0(rs)`.
    r.@add(ops[0]);
    r.@add(_rv_operand('#', 0, '0', '#'));
    r.@add(ops[1]);
    return [ mn: 'jalr', ops: r ];
  end if;
  if mn = 'jalr' and ops.@count() = 1 then
    r.@add(_rv_operand('r', 1, 'ra', 'r'));
    r.@add(_rv_operand('#', 0, '0', '#'));
    r.@add(ops[0]);
    return [ mn: 'jalr', ops: r ];
  end if;
  if mn = 'jr' and ops.@count() = 1 then
    r.@add(_rv_operand('r', 0, 'zero', 'r'));
    r.@add(_rv_operand('#', 0, '0', '#'));
    r.@add(ops[0]);
    return [ mn: 'jalr', ops: r ];
  end if;
  if mn = 'j' and ops.@count() = 1 then
    r.@add(_rv_operand('r', 0, 'zero', 'r'));
    r.@add(ops[0]);
    return [ mn: 'jal', ops: r ];
  end if;
  // The compact branch spellings expand to a comparison against zero.
  var zero = _rv_operand('r', 0, 'zero', 'r');
  if mn = 'beqz' and ops.@count() = 2 then
    r.@add(ops[0]); r.@add(zero); r.@add(ops[1]);
    return [ mn: 'beq', ops: r ];
  end if;
  if mn = 'bnez' and ops.@count() = 2 then
    r.@add(ops[0]); r.@add(zero); r.@add(ops[1]);
    return [ mn: 'bne', ops: r ];
  end if;
  if mn = 'blez' and ops.@count() = 2 then
    r.@add(zero); r.@add(ops[0]); r.@add(ops[1]);
    return [ mn: 'bge', ops: r ];
  end if;
  if mn = 'bgez' and ops.@count() = 2 then
    r.@add(ops[0]); r.@add(zero); r.@add(ops[1]);
    return [ mn: 'bge', ops: r ];
  end if;
  if mn = 'bltz' and ops.@count() = 2 then
    r.@add(ops[0]); r.@add(zero); r.@add(ops[1]);
    return [ mn: 'blt', ops: r ];
  end if;
  if mn = 'bgtz' and ops.@count() = 2 then
    r.@add(zero); r.@add(ops[0]); r.@add(ops[1]);
    return [ mn: 'blt', ops: r ];
  end if;
  result = nil;
end fun;

// `li rd, imm`: addi for the signed-12-bit range, otherwise lui + addi with
// the +0x800 rounding gas uses. Values outside signed 32 bits are rejected;
// build those explicitly from lui/addiw/slli.
fun _rv_li(words, rd, im)
  if im.typ <> '#' then
    raise 'li needs an immediate'.eval();
  end if;
  // Hex literals wider than 32 bits wrap in toNum (0x100000000 -> 0), so the
  // width is checked on the text before the numeric range test.
  var digits = im.text;
  if digits.substr(0, 1) = '#' then digits = digits.substr(1); end if;
  if digits.substr(0, 2).lower() = '0x' and digits.length() > 10 then
    raise 'li immediate wider than 32 bits: use lui/addiw/slli'.eval();
  end if;
  var v = im.num;
  if v >= -2048 and v <= 2047 then
    _rv_emit(words, 0x00000013 bit or (rd << 7) bit or ((v bit and 0xFFF) << 20));
    return;
  end if;
  if v < -2147483648 or v > 2147483647 then
    raise 'li immediate wider than 32 bits: use lui/addiw/slli'.eval();
  end if;
  var hi = (v + 0x800) >> 12;
  var lo = v - (hi << 12);
  _rv_emit(words, 0x00000037 bit or (rd << 7) bit or ((hi bit and 0xFFFFF) << 12));
  if lo <> 0 then
    // gas emits addiw (not addi) for the low half of an RV64 `li`, so the
    // 32-bit immediate is sign-extended into the 64-bit register.
    _rv_emit(words, 0x0000001B bit or (rd << 7) bit or (rd << 15)
             bit or ((lo bit and 0xFFF) << 20));
  end if;
end fun;

fun _rv_encode_line(line, words, fixups)
  var parts = line.match(/^(\S++)\s*(.*)$/);
  if parts.@@() = '' then return; end if;
  var mn = parts.@(1).lower();
  var rest = _rv_trim(parts.@(2));
  var ops = new [];
  if rest <> '' then
    for o in _rv_ops(rest) do _rv_class(o, ops); end do;
  end if;

  // table macro, e.g. "@sum1ton"
  if mn.substr(0, 1) = '@' then
    var hex = asms_rv[mn];
    if hex = nil then raise '$mn not found.'.eval(); end if;
    for i = 0 to (hex.length() div 8) - 1 do
      _rv_emit(words, _rv_leword(hex.substr(i*8, 8)));
    end do;
    return;
  end if;

  if mn = 'li' and ops.@count() = 2 then
    _rv_li(words, ops[0].num, ops[1]);
    return;
  end if;

  var ps = _rv_pseudo(mn, ops);
  if ps <> nil then
    mn = ps.mn;
    ops = ps.ops;
  end if;

  var br = _rv_branch_info(mn);
  var key = mn;
  if ops.@count() > 0 then
    key &= ' ';
    for i = 0 to ops.@count()-1 do
      if i > 0 then key &= ','; end if;
      // A numeric branch target shares the label entry: the offset is patched
      // below, the displacement is not a table slot.
      if br <> nil and i = ops.@count()-1 then
        key &= 'L';
      else
        key &= ops[i].shape;
      end if;
    end do;
  end if;
  var val = asms_rv[key];
  if val = nil then raise '$key not found.'.eval(); end if;
  var vp = split(/\|/, val);
  var w = ('0x' & vp[0]).toNum();
  for j = 1 to vp.@count()-1 do w = _rv_slot(w, vp[j], ops); end do;

  if br <> nil and ops.@count() > 0 then
    var last = ops[ops.@count()-1];
    if last.typ = 'lbl' then
      var f = new [];
      f.wi = words.@count(); f.bi = br; f.lbl = last.text;
      fixups.@add(f);
    elsif last.typ = '#' then
      if last.num mod 4 <> 0 then raise 'branch offset not a multiple of 4: $line'.eval(); end if;
      w = _rv_patch_branch(w, br, last.num);
    else
      raise 'branch target must be a label or #offset: $line'.eval();
    end if;
  end if;
  _rv_emit(words, w);
end fun;

// "67800000" (little-endian bytes) -> 0x00800067
fun _rv_leword(hex8)
  result = ('0x' & hex8.substr(6,2) & hex8.substr(4,2)
                  & hex8.substr(2,2) & hex8.substr(0,2)).toNum();
end fun;

fun _rv_hexle(w)
  result = int2hex(w bit and 0xFFFFFFFF);
end fun;

// ------------------------------------------------------------- the backend
class AssemblyRiscv64 = AssemblyBase()
  var arch    = 'riscv64';
  var ret_hex = '67800000'; // jalr x0, 0(ra)  (ret)

  fun Compile(c)
    if c !~ /^#!asm\b/ then
      return base.Compile(c);
    end if;
    var body = c.replace(/^#!asm\b(?:[:=]?[\x20\t]*+(\w*+:\w*+))?/, m->GetArgs(m));
    var words = new [];
    var labels = new [];
    var fixups = new [];
    for raw in split(/\r?\n/, body) do
      var line = _rv_strip(raw);
      if line <> '' then
        var lm = line.match(/^([A-Za-z_.$]\w*)\s*:\s*(.*)$/);
        if lm.@@() <> '' then
          labels[lm.@(1)] = words.@count() + 1; // +1: 0 = nil in Fun
          line = _rv_trim(lm.@(2));
        end if;
        if line <> '' then
          _rv_encode_line(line, words, fixups);
        end if;
      end if;
    end do;
    for fx in fixups do
      var tgt = labels[fx.lbl];
      if tgt = nil then raise 'label $fx.lbl not found'.eval(); end if;
      var d = ((tgt - 1) - fx.wi) * 4;
      words[fx.wi] = _rv_patch_branch(words[fx.wi], fx.bi, d);
    end do;
    var s = '';
    for w in words do s &= _rv_hexle(w); end do;
    result = s;
  end fun;
end class;

// ----------------------------------------------------------- icache flush
// RISC-V keeps the instruction cache coherent only through `fence.i`; on
// Linux the libgcc/libc `__clear_cache` helper does it. Bind it so a JIT
// call after writing code sees the new bytes, and refuse to run unflushed
// code on a riscv64 host when no helper resolved.
if _rv_cpu = 'riscv64' then
  var _rv_clr = nil;
  for lib in ['libc.so.6', 'libgcc_s.so.1'] do
    if _rv_clr = nil then
      try _rv_clr = lib.getapi('__clear_cache', 'pp:i'); except _rv_clr = nil; end try;
    end if;
  end do;
  if _rv_clr <> nil then _asm_flush = _rv_clr; end if;
end if;
