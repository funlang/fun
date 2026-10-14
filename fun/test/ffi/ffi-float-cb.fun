use 'fun/lib/lib-host.fun';

// libffitest is built per host by fun/test/ffi/build.sh (the runner builds
// it on demand): .so on Linux, .dylib on macOS.
var FFITEST = DyLib('./fun/test/ffi/libffitest.so', './fun/test/ffi/libffitest.dylib');

########################################
# Unix FFI (Linux / macOS): float callbacks, mixed register classes, string callbacks
########################################
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-float-cb.fun
########################################

// float callback (float arg + return via SSE)
var fcf   = FFITEST.getapi('fc', 'fc:f');
fun x2f(a)
  return a * 2;
end fun;
var cbF = x2f.@toCallback(nil, 'f:f');
?. fcf(4.0, cbF);      ?. ' <- fc(4.0,x2f) float cb expect 8';

// mixed GPR/XMM args -> double return
var mixsum = FFITEST.getapi('mixsum', 'idi:d');
?. mixsum(2, 1.5, 3);  ?. ' <- mixsum(2,1.5,3) expect 6.5';

// double callback invoked repeatedly, accumulated in C
var accf = FFITEST.getapi('acc', 'dic:d');
fun inc2(x)
  return x + 2;
end fun;
var cbAcc = inc2.@toCallback(nil, 'd:d');
?. accf(0.5, 4, cbAcc); ?. ' <- acc(0.5,4,+2)=2.5+3.5+4.5+5.5 expect 16';

// void callback called 5x (side effect via Fun global counter)
var walkf = FFITEST.getapi('walk', 'ic:v');
var cnt = 0;
fun bump(x)
  cnt += 1;
end fun;
var cbVoid = bump.@toCallback(nil, 'i:v');
?. walkf(5, cbVoid);
?. cnt;               ?. ' <- cnt after walk(5) expect 5';

// two distinct simultaneous callbacks into one native call
var twicef = FFITEST.getapi('twice_cb', 'icc:i');
fun triple(x)
  return x * 3;
end fun;
var cbTriple = triple.@toCallback(nil, 'i:i');
var cbInc2   = inc2.@toCallback(nil, 'i:i');
?. twicef(10, cbTriple, cbInc2); ?. ' <- twice_cb(10,*3,+2) expect 32';

// callback nested inside another callback (getapi reentrancy)
var apply1  = FFITEST.getapi('apply1', 'ic:i');
var strlf   = FFITEST.getapi('strl', 's:i');
fun nn(x)
  var L = strlf('abcdef');
  return x + L;
end fun;
var cbNN = nn.@toCallback(nil, 'i:i');
?. apply1(100, cbNN); ?. ' <- apply1(100, nn-> x+6) expect 106';
