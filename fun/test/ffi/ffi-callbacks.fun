use 'fun/lib/lib-host.fun';

// libffitest is built per host by fun/test/ffi/build.sh (the runner builds
// it on demand): .so on Linux, .dylib on macOS.
var FFITEST = DyLib('./fun/test/ffi/libffitest.so', './fun/test/ffi/libffitest.dylib');

########################################
# Unix FFI (Linux / macOS): callbacks (Fun function as native function pointer)
########################################
# f.@toCallback(type) wraps a Fun function into a libffi closure; getapi()
# passes it to C via the 'c' argument type. arg:ret type chars.
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-callbacks.fun
########################################

var apply1   = FFITEST.getapi('apply1',  'ic:i');   // int cb
var dapply   = FFITEST.getapi('dapply',  'dc:d');   // double cb
var sumvia   = FFITEST.getapi('sumvia',  'ic:i');  // int n + cb, repeated
var cb2f     = FFITEST.getapi('cb2',     'iic:i');  // int,int cb
var applyStr = FFITEST.getapi('applyStr','sc:i');   // string cb
var makef    = FFITEST.getapi('make',    'ic:s');   // cb returns string

// --- int callback ---
fun dbl(n)
  return n * 2;
end fun;
var cbInt = dbl.@toCallback(nil, 'i:i');
?. apply1(5, cbInt);   ?. ' <- apply1(5,dbl) expect 10';

// --- double callback ---
fun sq(x)
  return x * x;
end fun;
var cbDbl = sq.@toCallback(nil, 'd:d');
?. dapply(3.0, cbDbl); ?. ' <- dapply(3,sq) expect 9';

// --- two-int callback, single call ---
fun add(a, b)
  return a + b;
end fun;
var cb2 = add.@toCallback(nil, 'ii:i');
?. cb2f(2, 3, cb2);     ?. ' <- cb2(2,3,add) expect 5';

// --- two-int callback invoked repeatedly from C ---
?. sumvia(1, cb2);      ?. ' <- sumvia(1,add) expect 1';
?. sumvia(5, cb2);      ?. ' <- sumvia(5,add) expect 25';

// --- repeated independent cb2 calls (fresh marshalling each time) ---
?. cb2f(0, 1, cb2);     ?. ' <- cb2(0,1) expect 1';
?. cb2f(5, 6, cb2);     ?. ' <- cb2(5,6) expect 11';
?. cb2f(0, 0, cb2);     ?. ' <- cb2(0,0) expect 0';

// --- string argument reaching the Fun callback ---
fun isHello(a)
  if a = 'hello' then
    return 123;
  end if;
  return -1;
end fun;
var cbStr = isHello.@toCallback(nil, 's:i');
?. applyStr('hello', cbStr); ?. ' <- applyStr(hello) expect 123';
?. applyStr('world', cbStr); ?. ' <- applyStr(world) expect -1';

// --- Fun callback that returns a string ---
fun greet(x)
  return 'made-string';
end fun;
var cbRet = greet.@toCallback(nil, 'i:s');
?. makef(9, cbRet);     ?. ' <- make(9, greet) string return expect made-string';

// --- zero-argument callbacks (no args; int / void return) ---
var fire0i = FFITEST.getapi('fire0i', 'c:i');
var fire0  = FFITEST.getapi('fire0',  'c:v');
var zcnt = 0;
fun seven() return 7; end fun;
fun tick() zcnt += 1; end fun;
var cb7 = seven.@toCallback(nil, ':i');
?. fire0i(cb7);         ?. ' <- fire0i(seven) expect 7 (zero-arg cb, int ret)';
var cbV = tick.@toCallback(nil, ':v');
?. fire0(cbV);
?. zcnt;                ?. ' <- zcnt after fire0(tick) expect 1 (void cb)';
