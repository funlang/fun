// Runtime C compilation through the bundled Tiny C Compiler.
// Host-dependent: needs libtcc.so next to funcmd on Linux (built by
// make-linux-x86_64.sh from src/3rd/tcc; funcmd links -rpath $ORIGIN).
use 'fun/lib/lib-tcc.fun';

// TEMPORARY diagnostics for the macOS bring-up. Print on macOS only so the
// Linux snapshot is unchanged; remove once libtcc works on Darwin.
if 'host'.arg().getJson(fd: true).os = 'macos' then
  fun _dv(v)
    if v = nil then result = 'nil'; else result = '' & v; end if;
  end fun;
  var dbg = 'DBG';
  if tcc = nil then
    dbg &= ' tcc=nil';
  else
    dbg &= ' tcc=ok';
    try
      for _k: _v in tcc do dbg &= ' K:' & _k; end do;
    except
      dbg &= ' iter=err';
    end try;
    if tcc.New = nil then dbg &= ' NewFn=nil'; else dbg &= ' NewFn=ok'; end if;
    try
      var mf = 'libSystem.B.dylib'.getapi('malloc', 'n:p');
      var mp = mf(16);
      dbg &= ' malloc=' & _dv(mp);
    except
      dbg &= ' malloc=err';
    end try;
    var dts = tcc.New();
    dbg &= ' ts=' & _dv(dts);
    tcc.Options(dts, '-nostdlib -nostdinc -O2');
    var dc = tcc.Compile(dts, 'int dadd(int a, int b) { return a + b; }');
    dbg &= ' comp=' & _dv(dc);
    var dr = tcc.Reloc(dts, 1);
    dbg &= ' reloc=' & _dv(dr);
    var dp = tcc.Get(dts, 'dadd');
    dbg &= ' ptr=' & _dv(dp);
  end if;
  raise dbg;
end if;

// integer path
var add = ccompile(`int add(int a, int b) { return a + b; }`, 'ii:i');
?. add.call(3, 4);
add.del();

// recursion inside the compiled unit
var fib = ccompile(`int fib(int n) { return n < 2 ? n : fib(n-1) + fib(n-2); }`, 'i:i');
?. fib.call(20);
fib.del();

// double args/return (SSE register path)
var sq = ccompile(`double sq(double x) { return x * x; }`, 'd:d');
?. sq.call(1.5);
sq.del();

// Fun callback invoked from compiled C. 'C' is the Win32 cdecl marker; it must
// behave like 'i' on Linux too (this is what lib-jit's C path passes).
fun mul(x, y)
  result = x * y;
end fun;
var sum = ccompile(
  `int sum(int n, int (*test)(int, int)) { long long s = 0; for (int i = 1; i <= n; i++) s += test(i, 2); return (int)s; }`,
  'ic:i'
);
?. sum.call(5, mul.@toCallback(nil, 'ii:C', true));
sum.del();

// compile errors surface through tcc_set_error_func and yield nil, not a crash
var bad = ccompile(`int oops( { return 1; }`, 'i:i');
?. bad = nil;
