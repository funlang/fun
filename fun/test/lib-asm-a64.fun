// lib-asm-a64 on Linux: pure text -> machine-code encodings of the aarch64
// backend, plus (on an aarch64 host) one live JIT call to prove the mmap path
// and the icache flush work.
//
// The encoder is host-independent string/number work, so the snapshot is
// generated on any host (the CI host is x86_64); only the final "exec" line
// depends on the cpu and reads "skip" off aarch64. Host-dependent: needs the
// FFI/mmaps that lib-asm itself needs.
//
// AArch64 byte encodings here were cross-checked against the keystone/gas
// assembler for the same instructions (see fun/test/tools/asm-a64-diff.sh for
// the gcc-aarch64-linux-gnu-as + objdump route when that toolchain exists).
use 'fun/lib/lib-asm-a64.fun';

var cpu = 'host'.arg().getJson(fd: true).cpu;

// Compile one `#!asm` body and print its hex. A direct AssemblyA64 instance is
// used so this runs on any host: Load() (the only arch-gated entry) is never
// called here.
var enc = AssemblyA64('i:i', '', nil);
fun show(name, body)
  ?. name & ': ' & enc.Compile(body);
end fun;

show('addsub_imm', `#!asm
add x0, x1, #1
add x2, x3, #4096
sub x4, x5, #8
subs x6, x7, #16
cmp x8, #7
`);

show('addsub_boundary', `#!asm
add x0, x1, #4095
sub x2, x3, #4095
adds x4, x5, #4095
subs x6, x7, #4095
`);

show('addsub_reg', `#!asm
add x0, x1, x2
add x3, x4, x5, lsl #3
subs x6, x7, x8
neg x9, x10
cmp x11, x12
`);

show('cmn', `#!asm
cmn x0, #1
cmn w3, #7
`);

show('logic_reg', `#!asm
and x0, x1, x2
orr x3, x4, x5
eor x6, x7, x8
ands x9, x10, x11
tst x12, x13
mvn x14, x15
`);

show('logic_imm', `#!asm
and x0, x0, #0xff
orr x1, x1, #0xf
eor x2, x2, #0xff00
ands x3, x3, #0xffff
orr w4, w4, #0xf0
and w7, w7, #1
and x5, x5, #0xffff0000
orr x6, xzr, #0xffffffff
`);

show('movwide', `#!asm
movz x0, #0x1234
movz x1, #0x1234, lsl #16
movk x2, #0xabcd, lsl #48
movn x3, #0xff
movk w4, #0x1234, lsl #16
`);

show('mov_reg', `#!asm
mov x0, x1
mov w2, w3
mov x4, sp
mov sp, x5
mov w6, wsp
mov wsp, w0
`);

show('mov_imm', `#!asm
mov x0, #0
mov x1, #0xffff
mov x2, #0x10000
mov x3, #0xff00ff00
mov x4, #0x12345678
mov x5, #0xffffffff
mov x8, #0xdeadbeefcafeba
mov w6, #0xffffff00
`);

show('csel', `#!asm
csel x0, x1, x2, eq
csel x3, x4, x5, gt
csel w6, w7, w8, lt
csel x0, x1, x2, ne
csel x0, x1, x2, hi
`);

show('loadstore', `#!asm
ldr x0, [x1]
ldr x0, [x1, #8]
str w0, [x1, #4]
ldrb w0, [x1, #3]
strb w0, [x1, #2]!
ldr x1, [x1], #8
ldr x2, [x3, x4, lsl #3]
ldr x5, [x1, x2]
ldr w6, [x1, x2, lsl #2]
ldrb w7, [x1, x2, lsl #0]
`);

show('sp_loadstore', `#!asm
ldr x0, [sp, #16]
str w2, [sp, #12]
ldrb w1, [sp]
strh w3, [sp, #6]
`);

show('pair', `#!asm
stp x29, x30, [sp, #-16]!
ldp x29, x30, [sp], #16
stp x0, x1, [x2, #16]
ldp w0, w1, [sp]
`);

show('branch', `#!asm
mov x1, x0
mov x0, #0
loop:
add x0, x0, x1
subs x1, x1, #1
b.ne loop
ret
`);

show('branch0', `#!asm
loop:
add x0, x0, #1
cmp x0, #3
b.ne loop
ret
`);

show('branch_num', `#!asm
b #8
bl #-4
b.ne #-8
`);

show('call_sub', `#!asm
bl inc
ret
inc:
add x0, x0, #1
ret
`);

show('shift_ext', `#!asm
add w13, w14, w15, lsl #2
and x16, x17, x18, lsl #4
orr w19, w20, w21, lsl #3
eor x22, x23, x24, lsl #40
ands w25, w26, w27, lsl #5
tst x28, x29, lsl #1
mvn x30, x0, lsl #2
neg w1, w2, lsl #1
cmp w3, w4, lsl #6
ldrh w8, [x1]
strh w9, [sp], #4
ldrh w11, [x1, x2, lsl #1]
strb w12, [x1]
`);

show('misc', `#!asm
nop
br x9
blr x9
ret
`);

show('sum1ton', `#!asm
@sum1ton
`);

show('bcond_all', `#!asm
b.eq #0
b.ne #0
b.cs #0
b.cc #0
b.mi #0
b.pl #0
b.vs #0
b.vc #0
b.hi #0
b.ls #0
b.ge #0
b.lt #0
b.gt #0
b.le #0
b.al #0
`);

// `<name>` callback: address is host-specific, so only assert it encoded.
fun cb(a)
  result = a + 1;
end fun;
var named = AssemblyA64('i:i', '', [cb: cb.@toCallback(nil, 'i:i', true)]);
var ch = named.Compile(`#!asm
mov x9, <cb>
blr x9
ret
`);
?. 'callback: ' & ((ch.length() > 0) and 'encoded' or 'EMPTY');

// Out-of-range / misaligned operands must raise (gas rejects these too; the
// keystone oracle is lenient here, so this is asserted directly).
var rejected = 0;
for bad in ['ldr x0, [x1, #0x8000]', 'movz x0, #0x10000', 'stp x0, x1, [sp, #520]',
            'ldrb w0, [x1, #4096]', 'ldr x0, [x1, #7]', 'add x0, x1, #12345',
            'add x0, x1, #0x1000000', 'ldr x0, [x1, x2, lsl #2]',
            'ldr x0, [x1, w2]', 'ldr x0, [x1, x2, sxtw]',
            'orr w0, w1, w2, lsl #40', 'add w0, w1, w2, lsl #32'] do
  try
    enc.Compile('#!asm' & 10.toChar() & bad);
  except
    rejected += 1;
  end try;
end do;
?. 'range checks rejected: ' & rejected & '/12';

// Live execution only where the backend can run.
if cpu = 'arch64' then
  // Opt in with the class itself (lib-asm-pro does the same): an instance is
  // not callable as a constructor, so Assembly(...) below must see the class.
  Assembly = AssemblyA64;
  var dbl = Assembly('i:i', `#!asm
add x0, x0, x0
ret
`);
  dbl.Load();
  ?. 'exec: ' & dbl.Run(21);
  dbl.Delete();
else
  ?. 'exec: skip (cpu=' & cpu & ')';
end if;

?. 'ok';
