// lib-asm-loongarch64 on Linux: pure text -> machine-code encodings of the
// LoongArch64 backend, plus (on a LoongArch host) one live JIT call to prove
// the mmap path and the icache flush work.
//
// The encoder is host-independent string/number work, so the snapshot runs on
// any host (CI is x86_64); only the final "exec" line depends on the cpu.
//
// The expected words below were produced by GNU as 2.41 for the same
// instructions (see fun/test/tools/asm-loongarch64-diff.sh for the exhaustive
// differential run over fun/test/tools/loongarch64-cases.txt).
use 'fun/lib/lib-asm-loongarch64.fun';

var cpu = 'host'.arg().getJson(fd: true).cpu;

// Compile one `#!asm` body and print its hex. A direct instance is used so
// this runs on any host: Load() (the only cpu-gated entry) is never called
// here.
var enc = AssemblyLoongArch64('i:i', '', nil);
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

if not chk('addsub', `#!asm
addi.d $a0, $a0, 1
add.d $a0, $a0, $a1
sub.w $a2, $a3, $a4
and $a0, $a1, $a2
slli.d $a0, $a1, 4
ld.d $a0, $sp, 8
st.w $a0, $a1, -4
`, '8404C00284941000E6201100A4981400A41041006420C028A4F0BF29') then bad += 1; end if;

if not chk('li', `#!asm
li.w $a0, 0x12345
li.w $a1, -1
li.d $a2, 0x12345678
li.d $a3, 0x80000000
`, '4402001484148D0305FCBF02A6682414C6E099030700001507000016') then bad += 1; end if;

// Label resolution exercises all three branch split layouts: bnez is the
// 21-bit [5@0][16@10] form, beq the 16-bit @10 form, b the 26-bit
// [10@0][16@10] form.
if not chk('branch', `#!asm
loop:
addi.d $a0, $a0, 1
addi.d $a1, $a1, -1
bnez $a1, loop
beq $a0, $a1, done
b done
done:
ret
`, '8404C002A5FCFF02BFF8FF4785080058000400502000004C') then bad += 1; end if;

// Out-of-range / misaligned operands must raise (gas rejects these too).
var rejected = 0;
for b in ['addi.d $a0, $a1, 2048', 'andi $a0, $a1, 0x1000',
          'slli.d $a0, $a1, 64', 'ld.d $a0, $sp, 2048',
          'beq $a0, $a1, #7', 'lu52i.d $a0, $a1, 0x800',
          'li.d $a0, 0x123456789', 'lu12i.w $a0, 0x80000'] do
  try
    enc.Compile('#!asm' & 10.toChar() & b);
  except
    rejected += 1;
  end try;
end do;
?. 'range checks rejected: ' & rejected & '/8';
if rejected <> 8 then bad += 1; end if;

// A raw <name> in a 32-bit immediate must be rejected, not silently encoded
// as zero; a JIT snippet builds the address explicitly.
fun cb(a)
  result = a + 1;
end fun;
var named = AssemblyLoongArch64('i:i', '', [cb: cb.@toCallback(nil, 'i:i', true)]);
var name_rejected = false;
try
  named.Compile(`#!asm
lu12i.w $a0, <cb>
`);
except
  name_rejected = true;
end try;
?. 'callback address rejected: ' & (name_rejected and 'yes' or 'NO');
if not name_rejected then bad += 1; end if;

// Live execution only where the backend can run.
if cpu = 'loongarch64' then
  try
    Assembly = AssemblyLoongArch64;
    var inc = Assembly('i:i', `#!asm
addi.d $a0, $a0, 1
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
