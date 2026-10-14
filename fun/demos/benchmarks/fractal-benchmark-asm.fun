use 'lib-time.fun';
var t = tick();

use 'lib-asm-pro.fun';
#*
asms.@mandelbrot = '5589E583EC38D94508DD5DF0D9450CDD5DF8D9EEDD5DE8D9EEDD5DE066BA00006642DD45E8DC4DE0DD5DD8DD45E0DCC8DD5DD0DD45E8DCC8DD5DC8DD45C8DC6DD0DC45F8DD5DE0DD45D8DCC0DC45F0DD5DE8DD45D0DC45C8D94510DED9DFE09E73056689D1EB0B6681FAE8037EB266B900000FB7C1C9';
#

var asm = Assembly('fff:i', `#!asm
    ;xor eax, eax
    ;retn $000C
    @mandelbrot
`);
asm.Load();

fun main()
  for y = -39 to 38 loop
    var s = ''; //?. '';
    for x = -39 to 38 do
      if asm.Run(x/40, y/40-0.5, 16.0) = 0 then
        s &= '*'; //? '*';
      else
        s &= ' '; //? ' ';
      end if;
    end do;
    ?. s; //
  end loop;
  //?. '';
end fun;

?. t.show();
main();
?. t.show();
