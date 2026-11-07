// Clone/`new` hot-path benchmark.
//
// Measures the cost of constructing and deep-copying small collections. It is
// intentionally allocation-heavy: each iteration builds a set, a nested list,
// and a second set that clones the first one.
//
//   fun/funcmd fun/demos/benchmarks/clone-bench.fun
//
// The runner (run-clone-bench.sh) repeats it and reports the minimum and
// median wall time. Keep the loop count stable when comparing revisions.

use 'fun/lib/lib-time.fun';

var n = 100000;
var acc = 0;
var t = tick(-2);

for i = 1 to n do
  var a = new [x: i, y: i + 1, z: [i, i + 1]];
  var b = new [a: a, c: [i, i + 1]];
  acc += b.a.x + b.c[0];
end do;

?. 'clone-bench n=' & n & ' ms=' & t.get() & ' checksum=' & acc;
