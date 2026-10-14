use 'lib-asm-pro.fun';
use 'lib-time.fun';

test();
fun test()
  ?. date();
  ?. time();

  var t = tick(-2);
  var s = 0;
  for i = 1 to 1000000 do
    s += i;
  end do;
  ?: t.get();
  ?. s;
end fun;

test_asm();
fun test_asm()
  var ii = 0;
  fun cb(a, b)
    ii = a * 2^32 + b;
    ?, 'cb'; ?. ii;
    result = ii;
  end fun;

  var s = `#!asm
    mov ecx, dword ptr [esp+04]
    @sum1ton
    push eax
    push edx
    mov  eax, <test>
    call eax
  `; //?. s;

  var asm = Assembly('i:i', s, [test: cb.@toCallback(nil, 'ii:i', true)]);
  var i = 100000000;
  asm.Load();
  var t = tick(-2);
  asm.Run(i);
  ?: t.get();
  ?. ii; ?. int2hex(ii);
  asm.Delete();
  ?. 'Ok';
  ?. 2^32;
  ?. i / 2 * (i+1);
end fun;

#*
2026-8-11 13:23:13
13:23:13
143.192199853098        500000500000
cb 5.00000005E15
23.3613999065171        5.00000005E15
8070DB3A
Ok
4294967296
5.00000005E15
#
