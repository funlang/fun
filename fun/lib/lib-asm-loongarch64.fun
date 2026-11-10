// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-asm-loongarch64: the LoongArch64 backend of the hand-written-assembly
// path, sibling of lib-asm-pro.fun (x86) and lib-asm-a64.fun (AArch64).
//
// It shares the executable-memory plumbing, the `ret_hex` tail hook and the
// `<name>` callback resolver in lib-asm.fun; the encoder is per-architecture.
// See art/notes/loongarch-port-assessment.md and arch-machine-code-plan.md.
//
// Usage (the module deliberately does NOT grab the global `Assembly`; the
// script opts in, so `use`-ing several backends stays deterministic):
//
//   use 'lib-asm-loongarch64.fun';
//   Assembly = AssemblyLoongArch64;
//   var f = Assembly('i:i', `#!asm
//   addi.d $a0, $a0, 1
//   jr $ra
//   `);
//   f.Load(); ?. f.Run(41);
//
// ABI: the LoongArch LP64 ELF convention. Integer arguments a0-a7 ($r4-$r11),
// result a0, return address ra ($r1). A hand-written leaf function should only
// touch $r4-$r11, $r12-$r20 (t0-t8), and $r1; keep $sp 16-byte aligned.
//
// Encoding model: fixed-width 32-bit instructions with bit-fields, so the
// table format is a64's "<base word>|<slot>..." model, NOT x86's
// "append operand bytes". `asm-list-loongarch64.fd` is generated from the GNU
// binutils opcode table by
//   fun/lib/tools/gen-asm-list-loongarch64.py
// and checked byte-for-byte against loongarch64-linux-gnu-as by
//   fun/test/tools/asm-loongarch64-diff.sh
//
// Slot grammar (signed is 'y', not 'V'/'O': Fun's string comparison is
// case-insensitive, so signed/unsigned need different letters):
//   r<i>@b          GPR operand i at bit b
//   f<i>@b          FPR operand i at bit b
//   c<i>@b          FCC operand i at bit b
//   v<i>@b:w[:s]    unsigned immediate, w bits, value >> s
//   y<i>@b:w[:s]    signed immediate, w bits, value >> s
//
// Operand shapes: r = GPR, f = FPR, c = FCC, # = immediate, L = label
// (branch target), N = `<name>` callback address. Memory operands are plain
// three-operand forms (`ld.d $a0, $sp, 8`), not the a64 bracket syntax.
//
// Branch displacements: local labels are resolved in a second pass. LoongArch
// splits a displacement across field parts from the most significant end, so
// b/bl is [10 bits @0][16 bits @10], beqz/bnez is [5 bits @0][16 bits @10],
// and beq/bne/blt/bge/bltu/bgeu (plus the bltz family) is [16 bits @10].
// A numeric branch operand is a signed BYTE offset, as in the GNU assembler;
// labels are preferable unless you are hand-computing relative offsets.
//
// `li.w` / `li.d` are expanded here with the same chunking algorithm gas
// uses (lu12i.w / ori / addi.w / lu32i.d / lu52i.d). Immediates wider than
// signed 32 bits must be built explicitly with lu32i.d / lu52i.d for now.

use 'lib-asm.fun';
use 'lib-zlib.fun';
use 'lib-regex.fun';

var _la_cpu = 'host'.arg().getJson(fd: true).cpu;

// ---------------------------------------------------------------- the table
var asms_la = LAAsmsInit();
fun LAAsmsInit()
  if zlib then
    use ':asm-list-loongarch64.fd2.gz' as gz;
    result = inflate(gz).getJson(fd: true, sse: true);
  else
    raise 'lib-asm-loongarch64: zlib is required for the asm list';
  end if;
end fun;

// ------------------------------------------------------------- small helpers
fun _la_trim(s)
  result = s.replace(/^\s++|\s++$/g, '');
end fun;

fun _la_strip(line)
  result = _la_trim(line.replace(/;.*$/, ''));
end fun;

fun _la_ops(rest)
  var ops = new [];
  var cur = '';
  for i = 0 to rest.length()-1 do
    var ch = rest.substr(i, 1);
    if ch = ',' then
      ops.@add(_la_trim(cur));
      cur = '';
    else
      cur &= ch;
    end if;
  end do;
  if _la_trim(cur) <> '' then ops.@add(_la_trim(cur)); end if;
  result = ops;
end fun;

fun _la_num(t)
  var s = t;
  if s.substr(0, 1) = '#' then s = s.substr(1); end if;
  result = s.toNum();
end fun;

// GPR ABI names. LoongArch has no per-width register names: every GPR is
// 64-bit and the .w/.d suffix lives on the mnemonic.
var _LA_GPR = [ zero: 0, ra: 1, tp: 2, sp: 3,
                a0: 4, a1: 5, a2: 6, a3: 7, a4: 8, a5: 9, a6: 10, a7: 11,
                t0: 12, t1: 13, t2: 14, t3: 15, t4: 16, t5: 17, t6: 18,
                t7: 19, t8: 20, fp: 22,
                s0: 23, s1: 24, s2: 25, s3: 26, s4: 27, s5: 28, s6: 29,
                s7: 30, s8: 31 ];

fun _la_gprnum(s)
  var m = s.match(/^r(\d++)$/);
  if m.@@() <> '' then
    var n = m.@(1).toNum();
    if n > 31 then return -1; end if;
    return n;
  end if;
  // Only identifier-shaped names may index the ABI map: Fun map lookup coerces
  // a numeric string to a positional index, so _LA_GPR['4'] would return the
  // fifth value (4) and classify the immediate "4" as GPR 4 before any named
  // register has been looked up.
  if s.match(/^[a-z][a-z0-9]*$/).@@() = '' then return -1; end if;
  var v = _LA_GPR[s];
  if v <> nil then return v; end if;
  result = -1;
end fun;

// FPR names: $f0-$f31 plus the LP64 ABI aliases.
fun _la_fprnum(s)
  var m = s.match(/^f(\d++)$/);
  if m.@@() <> '' then
    var n = m.@(1).toNum();
    if n > 31 then return -1; end if;
    return n;
  end if;
  m = s.match(/^f([ast])(\d++)$/);
  if m.@@() <> '' then
    var k = m.@(1);
    var i = m.@(2).toNum();
    if k = 'a' and i <= 7 then return i; end if;                 // fa0-fa7  -> f0-f7
    if k = 't' and i <= 15 then return 8 + i; end if;            // ft0-ft15 -> f8-f23
    if k = 's' and i <= 7 then return 24 + i; end if;            // fs0-fs7  -> f24-f31
    return -1;
  end if;
  result = -1;
end fun;

fun _la_fccnum(s)
  var m = s.match(/^fcc(\d+)$/);
  if m.@@() <> '' then
    var n = m.@(1).toNum();
    if n > 7 then return -1; end if;
    return n;
  end if;
  result = -1;
end fun;

fun _la_operand(typ, num, text, shape)
  var r = new [];
  r.typ = typ; r.num = num; r.text = text; r.shape = shape;
  result = r;
end fun;

// Classify one operand and produce its table-lookup shape.
fun _la_class(t)
  var s = t;
  if s.substr(0, 1) = '$' then s = s.substr(1); end if;
  var n = _la_gprnum(s.lower());
  if n >= 0 then return _la_operand('r', n, t, 'r'); end if;
  n = _la_fccnum(s.lower());
  if n >= 0 then return _la_operand('c', n, t, 'c'); end if;
  n = _la_fprnum(s.lower());
  if n >= 0 then return _la_operand('f', n, t, 'f'); end if;
  if t.match(/^#?(-?(?:0x[0-9A-Fa-f]++|\d++))$/).@@() <> '' then
    return _la_operand('#', _la_num(t), t, '#');
  end if;
  if t.match(/^<(\w++)>$/).@@() <> '' then
    return _la_operand('name', 0, t.match(/^<(\w++)>$/).@(1), 'N');
  end if;
  return _la_operand('lbl', 0, t, 'L');
end fun;

// ------------------------------------------------------- slot -> word patcher
fun _la_slot(w, slot, ops)
  var m = slot.match(/^([rfcvy])(\d++)@(\d++)(?::(\d++))?(?::(\d++))?$/);
  if m.@@() = '' then raise 'bad slot: $slot'.eval(); end if;
  var op  = m.@(1);
  var i   = m.@(2).toNum();
  var pos = m.@(3).toNum();
  var wid = 5;
  if m.@(4) <> nil then wid = m.@(4).toNum(); end if;
  var sh = 0;
  if m.@(5) <> nil then sh = m.@(5).toNum(); end if;
  var o = ops[i];
  if o.typ = 'name' then
    raise '<callback> addresses do not fit a 32-bit field; use lu12i.w/lu32i.d/lu52i.d';
  end if;
  var val = 0;
  if op = 'r' or op = 'f' then
    val = o.num;
  elsif op = 'c' then
    wid = 3;
    val = o.num;
  else
    val = o.num;
    if sh > 0 then
      var unit = 1 << sh;
      if val mod unit <> 0 then raise 'immediate not a multiple of $unit'.eval(); end if;
      val = val div unit;
    end if;
    var mask0 = (1 << wid) - 1;
    if op = 'y' then
      if val < (0 - (1 << (wid-1))) or val > ((1 << (wid-1)) - 1) then
        raise 'signed immediate out of range: $slot'.eval();
      end if;
    else
      if val < 0 or val > mask0 then
        raise 'immediate out of range: $slot'.eval();
      end if;
    end if;
  end if;
  var mask = (1 << wid) - 1;
  result = w bit or ((val bit and mask) << pos);
end fun;

// --------------------------------------------------------- li.w / li.d alias
fun _la_sext(x, bits)
  var sign = 1 << (bits - 1);
  if (x bit and sign) <> 0 then result = x - (1 << bits); else result = x; end if;
end fun;

fun _la_emit(words, w)
  words.@add(w bit and 0xFFFFFFFF);
end fun;

// The gas chunking algorithm (gas/config/tc-loongarch.c, li.w/li.d): split
// the 64-bit value into 12/20/20/12-bit chunks and emit the shortest legal
// lu12i.w/ori/addi.w and lu32i.d/lu52i.d combination.
fun _la_li(words, rd, im, w64, names)
  var v = im.num bit and 0xFFFFFFFF;
  if im.typ = 'name' then
    raise 'li.w/li.d with a <callback> address is not supported; build it with lu12i.w/lu32i.d/lu52i.d';
  end if;
  var hi32 = 0;
  if w64 then
    // li.d takes a 64-bit literal: a positive hex constant such as
    // 0x80000000 has hi32 = 0, only a minus sign makes the high half all ones.
    var txt = im.text;
    if txt.substr(0, 1) = '#' then txt = txt.substr(1); end if;
    if txt.substr(0, 1) = '-' then hi32 = 0xFFFFFFFF; end if;
  else
    // li.w sign-extends the 32-bit value into the 64-bit register.
    if (v bit and 0x80000000) <> 0 then hi32 = 0xFFFFFFFF; end if;
  end if;
  if w64 then
    // Only signed-32-bit values are expanded for now; anything wider must be
    // assembled from lu32i.d/lu52i.d explicitly.
    if im.typ = '#' and im.text.match(/^#?(-?(?:0x[0-9A-Fa-f]++|\d++))$/).@@() <> '' then
      var digits = im.text;
      if digits.substr(0, 1) = '#' then digits = digits.substr(1); end if;
      if digits.substr(0, 2).lower() = '0x' then digits = digits.substr(2); end if;
      if digits.length() > 8 and digits.match(/^[0-9A-Fa-f]++$/).@@() <> '' then
        raise 'li.d immediate wider than 32 bits: use lu12i.w/lu32i.d/lu52i.d';
      end if;
    end if;
  end if;
  var c0 = v bit and 0xFFF;
  var c1 = (v >> 12) bit and 0xFFFFF;
  var c2 = hi32 bit and 0xFFFFF;
  var c3 = (hi32 >> 20) bit and 0xFFF;
  var all0 = 0; var allf = 0; var sgn = 0;
  if c0 = 0 then all0 = all0 bit or 1; end if;
  if c1 = 0 then all0 = all0 bit or 2; end if;
  if c2 = 0 then all0 = all0 bit or 4; end if;
  if c3 = 0 then all0 = all0 bit or 8; end if;
  if c0 = 0xFFF then allf = allf bit or 1; end if;
  if c1 = 0xFFFFF then allf = allf bit or 2; end if;
  if c2 = 0xFFFFF then allf = allf bit or 4; end if;
  if c3 = 0xFFF then allf = allf bit or 8; end if;
  if (c0 bit and 0x800) <> 0 then sgn = sgn bit or 1; end if;
  if (c1 bit and 0x80000) <> 0 then sgn = sgn bit or 2; end if;
  if (c2 bit and 0x80000) <> 0 then sgn = sgn bit or 4; end if;
  if (c3 bit and 0x800) <> 0 then sgn = sgn bit or 8; end if;
  var p = (all0 bit xor allf) bit and (all0 bit xor (sgn << 1));
  // lu12i.w / lu32i.d share the 1RI20 layout: rd[4:0], si20[24:5].
  if p = 7 then
    _la_emit(words, 0x03000000 bit or rd
             bit or ((_la_sext(c3, 12) bit and 0xFFF) << 10)); // lu52i.d rd,$r0,hi12
    return;
  end if;
  if (all0 bit and 3) = 2 then
    _la_emit(words, 0x03800000 bit or rd bit or ((c0 bit and 0xFFF) << 10)); // ori rd,$r0,lo12
  else
    var lo = p bit and 3;
    if lo = 0 then
      _la_emit(words, 0x14000000 bit or rd
               bit or ((_la_sext(c1, 20) bit and 0xFFFFF) << 5));   // lu12i.w
      _la_emit(words, 0x03800000 bit or rd bit or (rd << 5)
               bit or ((c0 bit and 0xFFF) << 10));                  // ori
    elsif lo = 1 then
      _la_emit(words, 0x14000000 bit or rd
               bit or ((_la_sext(c1, 20) bit and 0xFFFFF) << 5));   // lu12i.w
    elsif lo = 2 then
      _la_emit(words, 0x02800000 bit or rd
               bit or ((_la_sext(c0, 12) bit and 0xFFF) << 10));    // addi.w rd,$r0,lo12
    else
      _la_emit(words, 0x00150000 bit or rd bit or (0 << 5) bit or (0 << 10)); // or rd,$r0,$r0
    end if;
  end if
  var hi = p >> 2;
  if hi = 0 then
    _la_emit(words, 0x16000000 bit or rd
             bit or ((_la_sext(c2, 20) bit and 0xFFFFF) << 5));     // lu32i.d
    _la_emit(words, 0x03000000 bit or rd bit or (rd << 5)
             bit or ((_la_sext(c3, 12) bit and 0xFFF) << 10));      // lu52i.d
  elsif hi = 1 then
    _la_emit(words, 0x03000000 bit or rd bit or (rd << 5)
             bit or ((_la_sext(c3, 12) bit and 0xFFF) << 10));      // lu52i.d
  elsif hi = 2 then
    _la_emit(words, 0x16000000 bit or rd
             bit or ((_la_sext(c2, 20) bit and 0xFFFFF) << 5));     // lu32i.d
  end if;
end fun;

// ------------------------------------------------------------ branch fixups
// Field parts are listed most-significant first, matching LoongArch's split
// layout (binutils loongarch_decode_imm concatenates parts left to right).
fun _la_branch_info(mn)
  if mn = 'b' or mn = 'bl' then
    return [ parts: [[0,10],[10,16]], bits: 26 ];
  end if;
  if mn = 'beqz' or mn = 'bnez' or mn = 'bceqz' or mn = 'bcnez' then
    return [ parts: [[0,5],[10,16]], bits: 21 ];
  end if;
  if mn = 'beq' or mn = 'bne' or mn = 'blt' or mn = 'bge' or mn = 'bltu'
     or mn = 'bgeu' or mn = 'bltz' or mn = 'bgtz' or mn = 'bgez' or mn = 'blez' then
    return [ parts: [[10,16]], bits: 16 ];
  end if;
  result = nil;
end fun;

fun _la_patch_branch(w, bi, d)
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
fun _la_encode_line(line, words, fixups, names)
  var parts = line.match(/^(\S++)\s*(.*)$/);
  if parts.@@() = '' then return; end if;
  var mn = parts.@(1).lower();
  var rest = _la_trim(parts.@(2));
  var info = new [];
  if rest <> '' then
    for o in _la_ops(rest) do info.@add(_la_class(o)); end do;
  end if;

  // table macro, e.g. "@sum1ton"
  if mn.substr(0, 1) = '@' then
    var hex = asms_la[mn];
    if hex = nil then raise '$mn not found.'.eval(); end if;
    for i = 0 to (hex.length() div 8) - 1 do
      _la_emit(words, _la_leword(hex.substr(i*8, 8)));
    end do;
    return;
  end if;

  // li.w / li.d expand to several instructions
  if (mn = 'li.w' or mn = 'li.d') and info.@count() = 2 then
    _la_li(words, info[0].num, info[1], mn = 'li.d', names);
    return;
  end if;

  var key = mn;
  if info.@count() > 0 then
    key &= ' ';
    for i = 0 to info.@count()-1 do
      if i > 0 then key &= ','; end if;
      key &= info[i].shape;
    end do;
  end if;
  var val = asms_la[key];
  if val = nil then raise '$key not found.'.eval(); end if;
  var vp = split(/\|/, val);
  var w = ('0x' & vp[0]).toNum();
  for j = 1 to vp.@count()-1 do w = _la_slot(w, vp[j], info); end do;

  var br = _la_branch_info(mn);
  if br <> nil and info.@count() > 0 and info[info.@count()-1].typ = 'lbl' then
    // label target: resolved after all lines are read
    var f = new [];
    f.wi = words.@count(); f.bi = br; f.lbl = info[info.@count()-1].text;
    fixups.@add(f);
  elsif br <> nil and info.@count() > 0 and info[info.@count()-1].typ = '#' then
    // numeric target: a signed byte offset, as gas spells it
    var off = info[info.@count()-1].num;
    if off mod 4 <> 0 then raise 'branch offset not a multiple of 4: $line'.eval(); end if;
    w = _la_patch_branch(w, br, off div 4);
  elsif br <> nil and info.@count() > 0 then
    raise 'branch target must be a label or #offset: $line'.eval();
  end if;
  _la_emit(words, w);
end fun;

// "A420C002" (little-endian bytes) -> 0x02C020A4
fun _la_leword(hex8)
  result = ('0x' & hex8.substr(6,2) & hex8.substr(4,2)
                  & hex8.substr(2,2) & hex8.substr(0,2)).toNum();
end fun;

// -> "8404C002" for word 0x02C00484 (int2hex already emits LE bytes)
fun _la_hexle(w)
  result = int2hex(w bit and 0xFFFFFFFF);
end fun;

// ------------------------------------------------------------- the backend
class AssemblyLoongArch64 = AssemblyBase()
  var arch    = 'loongarch64';
  var ret_hex = '2000004C'; // jirl $r0, $r1, 0  (ret)

  // Refuse to execute on a host where no cache-flush symbol resolved: running
  // unflushed code after mmap is a silent-corruption bug, not a warning.
  fun Load(c)
    if _la_cpu = 'loongarch64' and _asm_flush = nil then
      raise 'lib-asm-loongarch64: no __clear_cache symbol; refusing to run unflushed code';
    end if;
    return base.Load(c);
  end fun;

  fun Compile(c)
    if c !~ /^#!asm\b/ then
      return base.Compile(c);
    end if;
    var body = c.replace(/^#!asm\b(?:[:=]?[\x20\t]*+(\w*+:\w*+))?/, m->GetArgs(m));
    var words = new [];
    var labels = new [];
    var fixups = new [];
    for raw in split(/\r?\n/, body) do
      var line = _la_strip(raw);
      if line <> '' then
        var lm = line.match(/^([A-Za-z_]\w*)\s*:\s*(.*)$/);
        if lm.@@() <> '' then
          labels[lm.@(1)] = words.@count() + 1; // +1: 0 = nil in Fun
          line = _la_trim(lm.@(2));
        end if;
        if line <> '' then
          _la_encode_line(line, words, fixups, names);
        end if;
      end if;
    end do;
    for fx in fixups do
      var tgt = labels[fx.lbl];
      if tgt = nil then raise 'label $fx.lbl not found'.eval(); end if;
      var d = (tgt - 1) - fx.wi;
      words[fx.wi] = _la_patch_branch(words[fx.wi], fx.bi, d);
    end do;
    var s = '';
    for w in words do s &= _la_hexle(w); end do;
    result = s;
  end fun;
end class;

// ----------------------------------------------------------- icache flush
// LoongArch does not keep I-cache and D-cache coherent: after writing code to
// mmap'd memory the instruction cache must be invalidated (ibar 0, which is
// what GCC's libgcc __clear_cache uses), or the cpu may execute stale bytes.
// Bind the libgcc/libc spelling and refuse to JIT silently if none is found.
if _la_cpu = 'loongarch64' then
  var _la_clr = nil;
  for lib in ['libc.so.6', 'libgcc_s.so.1'] do
    if _la_clr = nil then
      try _la_clr = lib.getapi('__clear_cache', 'pp:i'); except _la_clr = nil; end try;
    end if;
  end do;
  if _la_clr <> nil then _asm_flush = _la_clr; end if;
end if;
