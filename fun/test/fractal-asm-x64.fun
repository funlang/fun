// x86_64 SysV mandelbrot for lib-asm (Linux port validation)
// 签名 'ddd:i': xmm0 = ci (x/40), xmm1 = cr (y/40-0.5), xmm2 = 16.0 (limit)
// 逃逸返回 i, 未逃逸返回 0; 与 fractal-benchmark.fun 纯 Fun 版语义一致
use 'fun/lib/lib-time.fun';
use 'fun/lib/lib-asm.fun';

// 生成与反汇编验证脚本（不在仓库内）: scripts/gen-mandel.py (modrm = 0xC0|dst<<3|src)
var mandelbrot_x64 = '0F57DB0F57E431C0FFC0660F28EBF20F59ED660F28F4F20F59F6660F28FDF20F58FE660F2EFA7729660F28FBF20F59FCF20F5CEEF20F58E9660F28DDF20F58FFF20F58F8660F28E73DE80300007CB931C0C3';

var asm = Assembly('ddd:i', mandelbrot_x64);
asm.Load();

fun main()
  for y = -39 to 38 loop
    var s = '';
    for x = -39 to 38 do
      if asm.Run(x/40, y/40-0.5, 16.0) = 0 then
        s &= '*';
      else
        s &= ' ';
      end if;
    end do;
    ?. s;
  end loop;
end fun;

var t = tick(-2);
main();
?. 'x64 asm mandelbrot time: ' & t.get() & ' ms';
