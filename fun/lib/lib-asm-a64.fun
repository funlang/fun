// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-asm-a64: the AArch64 (ARM64) backend of the hand-written-assembly path.
//
// Sibling of lib-asm-pro.fun (x86/x86-64). Both share the executable-memory
// plumbing, the `ret_hex` tail hook and the `<name>` callback resolver in
// lib-asm.fun; the *encoder* is per-architecture, because AArch64 is a fixed
// 32-bit instruction set with bit-fields (Rd[4:0], Rn[9:5], Rm[20:16], ...)
// while x86 is a variable-length "append operand bytes" model. See
// art/notes/arch-machine-code-plan.md.
//
// Usage (the module deliberately does NOT grab the global `Assembly`; the
// script opts in, so `use`-ing both backends stays deterministic):
//
//   use 'lib-asm-a64.fun';
//   Assembly = AssemblyA64;
//   var f = Assembly('i:i', `#!asm
//   add x0, x0, #1
//   ret
//   `);
//   f.Load(); ?. f.Run(41);
//
// ABIs: AAPCS64 (arguments x0-x7, return x0). A hand-written leaf function
// should only touch x0-x17; SP must stay 16-byte aligned or the next `stp` /
// `ldp` / call faults with SIGBUS.
//
// Encoding model (table `asm-list-a64.fd`, built by
// fun/lib/tools/make-asm-list.fun exactly like the x86 table):
//
//   key   = "<mnemonic> <operand-shape>,...", e.g. "add x,x,#"
//   value = "<8 hex base word>|<slot>|<slot>...", e.g.
//           "91000000|r0@0|r1@5|q2"
//
// The base is the instruction word with every variable field zero. Each slot
// takes one operand field and ORs it, shifted, into fixed bits:
//   r<i>@b            register number of operand i, 5 bits
//   v<i>@b:w[:s]      immediate of operand i, >>s, w bits
//   b<i>@b            memory operand i base register
//   o<i>@b:w:s        memory operand i offset >>s, w bits
//   m<i>@b            memory operand i index register (register offset)
//   s<i>@b:w          shift operand i amount
//   h<i>@b:w          shift operand i as a MOVZ/MOVK hw code (0,16,32,48)
//   k<i>@b:w          condition operand i (eq..nv) as its 4-bit code
//   L<i>              logical (bitmask) immediate of operand i, N:immr:imms
//                     at bits 22..10, computed by _a64_logical
//   q<i>              ADD/SUB imm12 with automatic lsl#12 split
//
// Operand shapes: x/w = 64/32-bit register (sp/xzr map to 31), # = immediate,
// lsl/lsr/asr/ror = shift, c = condition, L = label, [x], [x#], [x#]!, [x+x],
// [x+xs] = memory forms (post-index is "[x]" followed by a separate # operand).
// Local labels and B/BL/B.cond fixups are resolved here in two passes. A
// numeric branch operand (`b #N`, `bl #N`, `b.cond #N`) is a signed BYTE
// offset from the branch instruction itself (the assembler-target-address
// reading that gas uses does not apply to this snippet assembler); use labels
// unless you are hand-computing an offset.

use 'lib-asm.fun';
use 'lib-zlib.fun';
use 'lib-regex.fun';

var _a64_cpu = 'host'.arg().getJson(fd: true).cpu;

// ---------------------------------------------------------------- the table
var asms_a64 = A64AsmsInit();
fun A64AsmsInit()
  if zlib then
    use ':asm-list-a64.fd.2.gz' as gz;
    result = inflate(gz).getJson(fd: true, sse: true);
  else
    raise 'lib-asm-a64: zlib is required for the asm list';
  end if;
end fun;

// ------------------------------------------------------------- small helpers
fun _a64_trim(s)
  result = s.replace(/^\s++|\s++$/g, '');
end fun;

fun _a64_strip(line)
  result = _a64_trim(line.replace(/;.*$/, ''));
end fun;

// Split on commas that are NOT inside [...] (so "[x1, #8]" stays one operand).
fun _a64_ops(rest)
  var ops = new [];
  var depth = 0;
  var cur = '';
  for i = 0 to rest.length()-1 do
    var ch = rest.substr(i, 1);
    if ch = '[' then depth += 1; end if;
    if ch = ']' then depth -= 1; end if;
    if ch = ',' and depth = 0 then
      ops.@add(_a64_trim(cur));
      cur = '';
    else
      cur &= ch;
    end if;
  end do;
  if _a64_trim(cur) <> '' then ops.@add(_a64_trim(cur)); end if;
  result = ops;
end fun;

// "#0x1f" / "31" / "-16" -> number
fun _a64_num(t)
  var s = t;
  if s.substr(0, 1) = '#' then s = s.substr(1); end if;
  result = s.toNum();
end fun;

fun _a64_regnum(t)
  var m = t.match(/^(x|w)(\d++)$/i);
  if m.@@() <> '' then
    return m.@(2).toNum();
  end if;
  if t = 'sp' or t = 'xzr' then return 31; end if;
  if t = 'wsp' or t = 'wzr' then return 31; end if;
  return -1;
end fun;

var _A64_CONDS = [ eq: 0, ne: 1, cs: 2, hs: 2, cc: 3, lo: 3, mi: 4, pl: 5,
                   vs: 6, vc: 7, hi: 8, ls: 9, ge: 10, lt: 11, gt: 12, le: 13,
                   al: 14, nv: 15 ];

// A memory operand: [base], [base, #off], [base, #off]!, [base, xm],
// [base, xm, lsl #s]. Post-index is written as "[base]" + a separate # operand.
fun _a64_mem(t)
  var pre = false;
  var s = t;
  if s.substr(0-1, 1) = '!' then
    pre = true;
    s = s.substr(0, s.length()-1);
  end if;
  var inner = s.substr(1, s.length()-2);
  var parts = _a64_ops(inner);
  var o = new [];
  // Presence flags, not nil tests: in Fun 0 = nil, so an offset of 0, index
  // register x0 or shift #0 would look absent.
  o.pre = pre; o.base = nil; o.off = nil; o.idx = nil; o.sh = nil;
  o.hasOff = false; o.hasIdx = false; o.hasSh = false;
  o.base = _a64_regnum(parts[0]);
  if o.base < 0 then raise 'bad memory base register: ' & t; end if;
  if parts.@count() > 1 then
    if parts[1].substr(0, 1) = '#' then
      o.off = _a64_num(parts[1]);
      o.hasOff = true;
    else
      // register offset: only the x-register LSL form is supported (no
      // w/uxtw/sxtw options), otherwise the encoding would be wrong
      if parts[1].match(/^x\d++$/i).@@() = '' then
        raise 'register offset index must be an x register: ' & t;
      end if;
      o.idx = _a64_regnum(parts[1]);
      o.hasIdx = true;
      if parts.@count() > 2 then
        var sc = _a64_class(parts[2]);
        if sc.typ <> 'lsl' then raise 'register offset supports only lsl #n: ' & t; end if;
        o.sh = sc.num;
        o.hasSh = true;
      end if;
    end if;
  end if;
  result = o;
end fun;

// Build a fresh operand record (array/map literals in Fun are shared
// constants, so every per-call record needs `new []`).
fun _a64_operand(typ, num, text, shape)
  var r = new [];
  r.typ = typ; r.num = num; r.text = text; r.shape = shape;
  result = r;
end fun;

// Classify one operand and (for memory) its lookup shape.
fun _a64_class(t)
  var m = t.match(/^(x|w)(\d++)$/i);
  if m.@@() <> '' then
    return _a64_operand(m.@(1).lower(), m.@(2).toNum(), t, m.@(1).lower());
  end if;
  if t = 'sp' or t = 'xzr' then
    return _a64_operand('x', 31, t, 'x');
  end if;
  if t = 'wsp' or t = 'wzr' then
    return _a64_operand('w', 31, t, 'w');
  end if;
  m = t.match(/^(lsl|lsr|asr|ror)\s*#?(-?\d++)$/i);
  if m.@@() <> '' then
    return _a64_operand(m.@(1).lower(), m.@(2).toNum(), '', m.@(1).lower());
  end if;
  m = t.match(/^#?(-?(?:0x[0-9A-Fa-f]++|\d++))$/);
  if m.@@() <> '' then
    return _a64_operand('#', _a64_num(t), t, '#');
  end if;
  m = t.match(/^<(\w++)>$/);
  if m.@@() <> '' then
    return _a64_operand('name', 0, m.@(1), 'N');
  end if;
  if t.substr(0, 1) = '[' then
    var mm = _a64_mem(t);
    var shp = '[x';
    if mm.hasIdx then
      shp &= '+x';
      if mm.hasSh then shp &= 's'; end if;
    elsif mm.hasOff then
      shp &= '#';
    end if;
    shp &= ']';
    if mm.pre then shp &= '!'; end if;
    var mo = _a64_operand('mem', 0, '', shp);
    mo.mem = mm;
    return mo;
  end if;
  if t.match(/^(eq|ne|cs|hs|cc|lo|mi|pl|vs|vc|hi|ls|ge|lt|gt|le|al|nv)$/i).@@() <> '' then
    return _a64_operand('c', _A64_CONDS[t.lower()], t, 'c');
  end if;
  return _a64_operand('lbl', 0, t, 'L');
end fun;

// ------------------------------------------------- bitmask logical immediate
// Largest element size (a power of two, len = log2) for which `lo`/`hi` is a
// single run of ones, replicated. Returns the 13-bit N:immr:imms field, or nil.
fun _a64_logical(lo, hi, w)
  var bits = new [];
  for i = 0 to w-1 do
    if i < 32 then
      bits.@add((lo >> i) bit and 1);
    else
      bits.@add((hi >> (i-32)) bit and 1);
    end if;
  end do;
  var len = 1;
  while (1 << len) <= w do
    var esize = 1 << len;
    var k = 1;
    while k < esize do
      var r = 0;
      while r < esize do
        var ok = true;
        for i = 0 to w-1 do
          var b = 0;
          if ((i + r) mod esize) < k then b = 1; end if;
          if b <> bits[i] then
            ok = false;
            exit;
          end if;
        end do;
        if ok then
          var n = 0;
          if len = 6 then n = 1; end if;
          var imms = (k - 1) bit or (0x3F bit and bit not ((1 << (len+1)) - 1));
          // +1: Fun has 0 = nil, and N:immr:imms = 0 is a valid field
          // (32-bit immediate #1); a bare 0 would compare equal to nil.
          return ((n << 12) bit or (r << 6) bit or imms) + 1;
        end if;
        r += 1;
      end do;
      k += 1;
    end do;
    len += 1;
  end do;
  result = nil;
end fun;

// ------------------------------------------------------- slot -> word patcher
fun _a64_slot(w, slot, ops)
  var typ = slot.substr(0, 1);
  if typ = 'q' then
    var v = ops[slot.substr(1).toNum()].num;
    if v < 0 then raise 'add/sub immediate must be non-negative: $v'.eval(); end if;
    if v > 0xFFF then
      if (v bit and 0xFFF) <> 0 or ((v >> 12) > 0xFFF) then
        raise 'add/sub immediate out of range: $v'.eval();
      end if;
      w = w bit or (1 << 22);
      v = v >> 12;
    end if;
    return w bit or ((v bit and 0xFFF) << 10);
  end if;
  if typ = 'L' then
    var li = slot.substr(1).toNum();
    var iw = 64;
    if ops[0].typ = 'w' then iw = 32; end if;
    // parse up to 64 bits from the literal TEXT (Fun ints are 32-bit)
    var it = ops[li].text;
    if it.substr(0, 1) = '#' then it = it.substr(1); end if;
    if it.substr(0, 2).lower() = '0x' then it = it.substr(2); end if;
    var lo = ops[li].num bit and 0xFFFFFFFF;
    var hi = 0;
    if it.length() > 8 then
      hi = ('0x' & it.substr(0, it.length()-8)).toNum();
      lo = ('0x' & it.substr(it.length()-8)).toNum();
    end if;
    var lf = _a64_logical(lo, hi, iw);
    if lf = nil then raise 'not a logical immediate: $slot'.eval(); end if;
    return w bit or ((lf - 1) << 10);
  end if;
  // Z<i>@<bpos>:<size>: the register-offset S bit. Set for `lsl #size` (size =
  // log2 element size) and for an explicit lsl#0 on a byte access; clear for
  // lsl#0 on larger accesses; anything else is a mismatch gas rejects.
  if typ = 'Z' then
    var zm = slot.match(/^Z(\d++)@(\d++):(\d++)$/);
    if zm.@@() = '' then raise 'bad Z slot: $slot'.eval(); end if;
    var mm = ops[zm.@(1).toNum()].mem;
    var zb = zm.@(2).toNum();
    var zs = zm.@(3).toNum();
    var set = false;
    if mm.hasSh then
      if mm.sh = 0 then
        if zs = 0 then set = true; end if;
      elsif mm.sh = zs then
        set = true;
      else
        raise 'register-offset shift does not match element size: $slot'.eval();
      end if;
    end if;
    if set then return w bit or (1 << zb); end if;
    return w;
  end if;
  var m = slot.match(/^([rvobmshkYD])(\d++)@(\d++)(?::(\d++))?(?::(\d++))?$/);
  if m.@@() = '' then raise 'bad slot: $slot'.eval(); end if;
  var op = m.@(1);
  var i  = m.@(2).toNum();
  var bpos = m.@(3).toNum();
  var wid = 5;
  if m.@(4) <> nil then wid = m.@(4).toNum(); end if;
  var sh = 0;
  if m.@(5) <> nil then sh = m.@(5).toNum(); end if;
  // Y/D = signed field (pre/post index imm9, stp/ldp imm7). Distinct letters,
  // not O/V: Fun's `=` on strings is case-insensitive, so 'o' = 'O'.
  var signed = false;
  if op = 'Y' then op = 'o'; signed = true; end if;
  if op = 'D' then op = 'v'; signed = true; end if;
  var o = ops[i];
  var val = 0;
  var mask = (1 << wid) - 1;
  if op = 'r' then
    val = o.num;
  elsif op = 'b' then
    val = o.mem.base;
  elsif op = 'm' then
    val = o.mem.idx;
  elsif op = 'o' then
    val = o.mem.off;
  elsif op = 'k' then
    val = o.num;
  elsif op = 's' then
    val = o.num;
    // a 32-bit shifted-register instruction only has 5 usable shift bits
    var smax = 63;
    if ops[0].typ = 'w' then smax = 31; end if;
    if val < 0 or val > smax then raise 'shift amount out of range for this register size: $slot'.eval(); end if;
  elsif op = 'h' then
    if o.num <> 0 and o.num <> 16 and o.num <> 32 and o.num <> 48 then
      raise 'shift must be 0/16/32/48: $slot'.eval();
    end if;
    val = o.num >> 4;
  elsif op = 'v' then
    val = o.num;
  end if;
  if op = 'o' or op = 'v' then
    // memory offset / immediate: scale to the field unit, then range-check
    var scaled = val;
    if sh > 0 then
      if val mod (1 << sh) <> 0 then raise 'offset not a multiple of the element size: $slot'.eval(); end if;
      scaled = val div (1 << sh);
    end if;
    if signed then
      if scaled < (0 - (1 << (wid-1))) or scaled > ((1 << (wid-1)) - 1) then
        raise 'signed immediate out of range: $slot'.eval();
      end if;
    else
      if scaled < 0 or scaled > mask then raise 'immediate out of range: $slot'.eval(); end if;
    end if;
    val = scaled;
  end if;
  val = val bit and mask;
  result = w bit or (val << bpos);
end fun;

// --------------------------------------------------- mov / move-wide helpers
// chunks[0] = bits 0..15, chunks[1] = bits 16..31, ...
fun _a64_movwide(words, rd, chunks, w64)
  var mz = 0xD2800000;
  var mk = 0xF2800000;
  if not w64 then
    mz = 0x52800000;
    mk = 0x72800000;
  end if;
  var hi = 0;
  for i = 0 to chunks.@count()-1 do
    if chunks[i] <> 0 then hi = i; end if;
  end do;
  words.@add(mz bit or (hi << 21) bit or ((chunks[hi] bit and 0xFFFF) << 5) bit or rd);
  for j = 0 to chunks.@count()-1 do
    if j <> hi and chunks[j] <> 0 then
      words.@add(mk bit or (j << 21) bit or ((chunks[j] bit and 0xFFFF) << 5) bit or rd);
    end if;
  end do;
end fun;

// 16-bit chunks of a hex string, 0 = least significant chunk.
fun _a64_hexchunks(hex)
  var h = hex.upper();
  if h.substr(0, 2) = '0X' then h = h.substr(2); end if;
  // left-pad to a whole number of 4-digit groups, else the top partial group
  // (e.g. 15 hex digits) is dropped
  while h.length() mod 4 <> 0 do h = '0' & h; end do;
  if h.length() > 16 then raise 'immediate wider than 64 bits: $hex'.eval(); end if;
  var chunks = new [];
  var n = h.length();
  for i = 0 to (n div 4) - 1 do
    chunks.@add(('0x' & h.substr(n - (i+1)*4, 4)).toNum());
  end do;
  result = chunks;
end fun;

// `mov xD, sp` / `mov sp, xN` are ADD (immediate) with #0, not ORR; sp and
// xzr both encode 31 but mean different things, so they cannot share `mov x,x`.
fun _a64_mov_sp(words, a, b)
  var base = 0x91000000;
  if a.typ = 'w' then base = 0x11000000; end if;
  var bs = b.text.lower();
  if bs = 'sp' or bs = 'wsp' then
    words.@add(base bit or (31 << 5) bit or a.num);
  else
    words.@add(base bit or (b.num << 5) bit or 31);
  end if;
end fun;

// `mov xD, #imm` / `mov wD, #imm` / `mov xD, <cb>`: the alias the assembler
// would pick. Order: MOVZ, MOVN, ORR (bitmask immediate), else MOVZ+MOVK.
fun _a64_mov(words, rd, im, names)
  var w64 = rd.typ = 'x';
  if im.typ = 'name' then
    _a64_movwide(words, rd.num, _a64_hexchunks(_nameAddr(im.text, names)), w64);
    return;
  end if;
  var txt = im.text;
  if txt.substr(0, 1) = '#' then txt = txt.substr(1); end if;
  var digits = txt;
  if digits.substr(0, 2).lower() = '0x' then digits = digits.substr(2); end if;
  if digits.length() > 8 and digits.match(/^[0-9A-Fa-f]++$/).@@() <> '' then
    // a genuinely 64-bit literal: chunk the text (Fun ints are 32-bit)
    if not w64 then raise 'immediate too wide for a w register: $digits'.eval(); end if;
    _a64_movwide(words, rd.num, _a64_hexchunks(digits), w64);
    return;
  end if;
  var v = im.num bit and 0xFFFFFFFF;
  var mz = 0xD2800000;
  var mn = 0x92800000;
  if not w64 then
    mz = 0x52800000;
    mn = 0x12800000;
  end if;
  var c0 = v bit and 0xFFFF;
  var c1 = (v >> 16) bit and 0xFFFF;
  var nz = 0;
  if c0 <> 0 then nz += 1; end if;
  if c1 <> 0 then nz += 1; end if;
  if nz <= 1 then
    // a single 16-bit chunk -> MOVZ (the assembler's first choice)
    var hw = 0;
    var imm = c0;
    if c0 = 0 and c1 <> 0 then hw = 1; imm = c1; end if;
    words.@add(mz bit or (hw << 21) bit or ((imm bit and 0xFFFF) << 5) bit or rd.num);
    return;
  end if;
  if not w64 then
    // 32-bit only: MOVN when the complement is a single chunk (=-1 is 0 chunks)
    var n0 = (bit not c0) bit and 0xFFFF;
    var n1 = (bit not c1) bit and 0xFFFF;
    var nz2 = 0;
    if n0 <> 0 then nz2 += 1; end if;
    if n1 <> 0 then nz2 += 1; end if;
    if nz2 <= 1 then
      var hw2 = 0;
      var imm2 = n0;
      if n0 = 0 and n1 <> 0 then hw2 = 1; imm2 = n1; end if;
      words.@add(mn bit or (hw2 << 21) bit or ((imm2 bit and 0xFFFF) << 5) bit or rd.num);
      return;
    end if;
  end if;
  var iw = 64;
  var orr = 0xB2000000;
  if not w64 then
    iw = 32;
    orr = 0x32000000;
  end if;
  var lf = _a64_logical(v, 0, iw);
  if lf <> nil then
    words.@add(orr bit or ((lf - 1) << 10) bit or 0x3E0 bit or rd.num);
    return;
  end if;
  var ch = new [];
  ch.@add(c0);
  ch.@add(c1);
  _a64_movwide(words, rd.num, ch, w64);
end fun;

// ------------------------------------------------------------ line encoder
fun _a64_branch_bits(mn)
  if mn = 'b' or mn = 'bl' then return [ bpos: 0, wid: 26 ]; end if;
  if mn.substr(0, 2) = 'b.' then return [ bpos: 5, wid: 19 ]; end if;
  result = nil;
end fun;

fun _a64_encode_line(line, words, fixups, names)
  var parts = line.match(/^(\S++)\s*(.*)$/);
  if parts.@@() = '' then return; end if;
  var mn = parts.@(1).lower();
  var rest = _a64_trim(parts.@(2));
  var info = new [];
  if rest <> '' then
    for o in _a64_ops(rest) do info.@add(_a64_class(o)); end do;
  end if;

  // table macro, e.g. "@sum1ton"
  if mn.substr(0, 1) = '@' then
    var hex = asms_a64[mn];
    if hex = nil then raise '$mn not found.'.eval(); end if;
    for i = 0 to (hex.length() div 8) - 1 do
      words.@add(_a64_leword(hex.substr(i*8, 8)));
    end do;
    return;
  end if;

  // mov alias with an immediate or a <callback> address
  if mn = 'mov' and info.@count() = 2 and (info[1].typ = '#' or info[1].typ = 'name') then
    _a64_mov(words, info[0], info[1], names);
    return;
  end if;
  // mov involving sp is ADD-imm #0, not ORR
  if mn = 'mov' and info.@count() = 2
     and (info[0].text.lower() = 'sp' or info[1].text.lower() = 'sp'
          or info[0].text.lower() = 'wsp' or info[1].text.lower() = 'wsp') then
    _a64_mov_sp(words, info[0], info[1]);
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
  var val = asms_a64[key];
  if val = nil then raise '$key not found.'.eval(); end if;
  var vp = split(/\|/, val);
  var w = ('0x' & vp[0]).toNum();
  for j = 1 to vp.@count()-1 do w = _a64_slot(w, vp[j], info); end do;

  // B/BL/B.cond to a local label: record a fixup resolved in the second pass.
  var br = _a64_branch_bits(mn);
  if br <> nil and info.@count() > 0 and info[0].typ = 'lbl' then
    var f = new [];
    f.wi = words.@count(); f.bpos = br.bpos; f.wid = br.wid; f.lbl = info[0].text;
    fixups.@add(f);
  elsif br <> nil and info.@count() > 0 and info[0].typ <> '#' then
    raise 'branch target must be a label or #offset: $line'.eval();
  end if;
  words.@add(w);
end fun;

// "20040091" (little-endian bytes) -> 0x91000420
fun _a64_leword(hex8)
  result = ('0x' & hex8.substr(6,2) & hex8.substr(4,2)
                  & hex8.substr(2,2) & hex8.substr(0,2)).toNum();
end fun;

// ------------------------------------------------------------- the backend
class AssemblyA64 = AssemblyBase()
  var arch    = 'arch64';
  var ret_hex = 'C0035FD6';

  fun Compile(c)
    if c !~ /^#!asm\b/ then
      return base.Compile(c);
    end if;
    // [\x20\t]*+ (space/tab, not \s): possessive \s would eat the newline and
    // then let the optional type-spec group swallow a label that is the first
    // body line. (A literal space inside a Fun regex class is a parse error;
    // \x20 is required.)
    var body = c.replace(/^#!asm\b(?:[:=]?[\x20\t]*+(\w*+:\w*+))?/, m->GetArgs(m));
    var words = new [];
    var labels = new [];
    var fixups = new [];
    for raw in split(/\r?\n/, body) do
      var line = _a64_strip(raw);
      if line <> '' then
        var lm = line.match(/^([A-Za-z_]\w*)\s*:\s*(.*)$/);
        if lm.@@() <> '' then
          labels[lm.@(1)] = words.@count() + 1; // +1: 0 = nil in Fun
          line = _a64_trim(lm.@(2));
        end if;
        if line <> '' then
          _a64_encode_line(line, words, fixups, names);
        end if;
      end if;
    end do;
    for fx in fixups do
      var tgt = labels[fx.lbl];
      if tgt = nil then raise 'label $fx.lbl not found'.eval(); end if;
      var d = (tgt - 1) - fx.wi;
      var mask = (1 << fx.wid) - 1;
      if d > (mask >> 1) or d < 0 - (mask >> 1) - 1 then
        raise 'branch out of range: $fx.lbl'.eval();
      end if;
      words[fx.wi] = words[fx.wi] bit or ((d bit and mask) << fx.bpos);
    end do;
    var s = '';
    for w in words do s &= int2hex(w); end do;
    result = s;
  end fun;
end class;

// ----------------------------------------------------------- icache flush
// aarch64 does not keep I-cache and D-cache coherent: after writing code to
// mmap'd memory it MUST be flushed or the cpu may execute stale bytes. Darwin
// spells it sys_icache_invalidate (libSystem); on Linux glibc does not provide
// __clear_cache on every ABI (it lives in libgcc on aarch64), so try the usual
// spellings; refuse to JIT silently if none is found.
if _a64_cpu = 'arch64' then
  var _clr = nil;
  if _asm_macos then
    try _clr = 'libSystem.B.dylib'.getapi('sys_icache_invalidate', 'pp:v'); except _clr = nil; end try;
  end if;
  for lib in ['libc.so.6', 'libgcc_s.so.1'] do
    if _clr = nil then
      try _clr = lib.getapi('__clear_cache', 'pp:i'); except _clr = nil; end try;
    end if;
  end do;
  if _clr = nil then
    try _clr = 'libc.so.6'.getapi('cacheflush', 'pp:i'); except _clr = nil; end try;
  end if;
  if _clr = nil then
    raise 'lib-asm-a64: no cache-flush symbol; refusing to run unflushed code';
  end if;
  _asm_flush = _clr;
end if;
