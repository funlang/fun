// `var` arguments are positional and by-reference. The referenced variable's
// name must never be passed as a named argument: COM IDispatch and the builtins
// that look arguments up by name (CExps.Find) share the same argument list.
fun inc(x)
  x += 1;
end fun;

fun f()
  var k = 1;
  ?. 'abcdef'.substr(var k);          // positional var arg
  ?. 'abcdef'.substr(pos: var k);     // explicit named var arg still binds
  var m = 2;
  ?. 'abcdef'.substr(pos: var m);
  inc(var k);
  ?. k;                               // by-reference write back
end fun;
f();

// Named-argument binding must survive a function that passes one of its own
// parameters on as `var`: the formal parameter node is shared with that call.
fun down(n, acc)
  if n <= 0 then
    return;
  end if;
  acc += n;
  down(n - 1, var acc);
end fun;

fun g()
  var t = 0;
  down(acc: var t, n: 3);
  ?. t;
end fun;
g();

// A bare var argument must not be found by the referenced variable's name.
fun pair(a, b)
  ?. a & ',' & b;
end fun;

fun h()
  var b = 9;
  pair(var b, 1);
end fun;
h();
