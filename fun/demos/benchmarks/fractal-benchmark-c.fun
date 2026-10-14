use 'lib-time.fun';
var t = tick();
use 'lib-tcc.fun';

var mandelbrot = ccompile(`
#define BAILOUT 16
#define MAX_ITERATIONS 1000

int mandelbrot(float x, float y)
{
	double cr = y - 0.5;
	double ci = x;
	double zi = 0.0;
	double zr = 0.0;
	int i = 0;

	while(1) {
		i ++;
		double temp = zr * zi;
		double zr2 = zr * zr;
		double zi2 = zi * zi;
		zr = zr2 - zi2 + cr;
		zi = temp + temp + ci;
		if (zi2 + zr2 > BAILOUT)
			return i;
		if (i > MAX_ITERATIONS)
			return 0;
	}

}
`, 'ff:i');

fun main()
  for y = -39 to 38 loop
    var s = ''; //?. '';
    for x = -39 to 38 do
      if mandelbrot.call(x/40, y/40) = 0 then
        s &= '*'; //? '*';
      else
        s &= ' '; //? ' ';
      end if;
    end do;
    ?. s; //
  end loop;
  //?. '';
  mandelbrot.del();
end fun;

?. t.show();
main();
?. t.show();
