// lib-asm-riscv64 on Linux: pure text -> machine-code encodings of the
// RISC-V 64 backend, plus (on a riscv64 host) one live JIT call to prove the
// mmap path and the icache flush work.
//
// The encoder is host-independent string/number work, so the snapshot runs on
// any host (CI is x86_64); only the final "exec" line depends on the cpu.
//
// The expected words below were produced by GNU as 2.44 for the same
// instructions (see fun/test/tools/asm-riscv64-diff.sh for the exhaustive
// differential run over fun/test/tools/riscv64-cases.txt).
use 'fun/lib/lib-asm-riscv64.fun';

var cpu = 'host'.arg().getJson(fd: true).cpu;

// Compile one `#!asm` body and print its hex. A direct instance is used so
// this runs on any host: Load() (the only cpu-gated entry) is never called
// here.
var enc = AssemblyRiscv64('i:i', '', nil);
var bad = 0;

fun chk(name, body, want)
  var got = enc.Compile(body);
  if got.upper() <> want.upper() then
    ?. 'FAIL ' & name & ': got ' & got & ' want ' & want;
    result = false;
  else
    ?. name & ': ' & got;
    result = true;
  end if;
end fun;

if not chk('arith', `#!asm
add a0, a1, a2
addi a0, a1, -2048
sub a2, a3, a4
and a0, a1, a2
andi a0, a1, 0x7ff
slli a0, a1, 4
srli a0, a1, 63
srai a0, a1, 32
addw a0, a1, a2
addiw a0, a1, 1
sllw a0, a1, a2
sraw a0, a1, a2
mul a0, a1, a2
divu a0, a1, a2
remw a0, a1, a2
`, '3385C500138505803386E64033F5C50013F5F57F1395450013D5F50313D505423B85C5001B8515003B95C5003BD5C5403385C50233D5C5023BE5C502') then bad += 1; end if;

if not chk('memory', `#!asm
ld a0, 8(sp)
sd a0, -2048(sp)
lw a0, 4(sp)
sw a0, 0(sp)
lb a0, -1(a1)
sb a0, 2047(a1)
lhu a0, 2(a1)
sh a0, 6(a1)
`, '033581002330A180032541002320A1000385F5FFA38FA57E03D525002393A500') then bad += 1; end if;

// Label resolution covers the B-type split layout (bnez/blt), the J-type
// layout (j) and the ra-defaulting `ret`.
if not chk('branch', `#!asm
loop:
addi a0, a0, 1
addi a1, a1, -1
bnez a1, loop
blt a0, a1, done
j done
done:
ret
`, '130515009385F5FFE39C05FE6344B5006F00400067800000') then bad += 1; end if;

if not chk('csr', `#!asm
csrrw a0, 0x300, a1
csrrs a0, 0x300, a1
csrrc a0, 0xc00, zero
csrrwi a0, 0x7c0, 0
csrrsi a0, 0x100, 1
csrrci a0, 0x300, 31
`, '7395053073A50530733500C07355007C73E5001073F50F30') then bad += 1; end if;

// `li` expands exactly like gas: addi inside the signed-12-bit range,
// otherwise lui + addiw.
if not chk('li', `#!asm
li a0, 0x12345
li a1, -5
li a2, 0x7ff
li a3, -2048
li a4, 0x7f000
`, '372501001B0555349305B0FF1306F07F9306008037F70700') then bad += 1; end if;

// Pseudo-instructions and numeric branch offsets (signed BYTE offsets, as in
// the GNU assembler).
if not chk('misc', `#!asm
ecall
ebreak
wfi
fence.i
nop
mv a0, a1
jal #-16
jalr a0
beqz a0, #8
bgez a0, #8
`, '7300000073001000730050100F1000001300000013850500EFF01FFFE70005006304050063540500') then bad += 1; end if;

// Out-of-range / misaligned operands must raise (gas rejects these too).
var rejected = 0;
for b in ['addi a0, a1, 2048', 'slli a0, a1, 64',
          'ld a0, 2048(sp)', 'beq a0, a1, #2',
          'li a0, 0x100000000', 'csrrw a0, 0x1000, a1',
          'addi a0, a1, 1, 2'] do
  try
    enc.Compile('#!asm' & 10.toChar() & b);
  except
    rejected += 1;
  end try;
end do;
?. 'range checks rejected: ' & rejected & '/7';
if rejected <> 7 then bad += 1; end if;

// Live execution only where the backend can run.
if cpu = 'riscv64' then
  try
    Assembly = AssemblyRiscv64;
    var inc = Assembly('i:i', `#!asm
addi a0, a0, 1
ret
`);
    inc.Load();
    var r = inc.Run(41);
    ?. 'exec: ' & r;
    if r <> 42 then bad += 1; end if;
    inc.Delete();
  except
    // Emulated/sysroot environments may have no __clear_cache (libgcc_s is
    // not part of the qemu sysroot); the encoder snapshot above still holds.
    ?. 'exec: skip';
  end try;
else
  ?. 'exec: skip';
end if;

if bad <> 0 then
  ?. 'FAILED: ' & bad;
else
  ?. 'ok';
end if;
