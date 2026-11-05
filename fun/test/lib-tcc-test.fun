// Runtime C compilation through the bundled Tiny C Compiler.
// Host-dependent: needs libtcc.so next to funcmd on Linux (built by
// make-linux-x86_64.sh from src/3rd/tcc; funcmd links -rpath $ORIGIN).
use 'fun/lib/lib-tcc.fun';

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
