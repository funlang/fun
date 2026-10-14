use 'fun/lib/lib-host.fun';

// libffitest is built per host by fun/test/ffi/build.sh (the runner builds
// it on demand): .so on Linux, .dylib on macOS.
var FFITEST = DyLib('./fun/test/ffi/libffitest.so', './fun/test/ffi/libffitest.dylib');

########################################
# Unix FFI (Linux / macOS): 64-bit integer ('l') args/returns + callback roundtrip
########################################
# NOTE: Fun's own numeric literals/arithmetic wrap at 32-bit, so feed true
# 64-bit values in from C (e.g. big64) rather than from a Fun literal. The FFI
# itself carries full 64-bit values in both directions.
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-int64.fun
########################################

var bigf  = FFITEST.getapi('big64',  ':l');
var passf = FFITEST.getapi('passll','l:l');
var addf  = FFITEST.getapi('addll', 'll:l');
var applyllf = FFITEST.getapi('applyll','lc:l');

var b = bigf();                    // 0x100000005 = 4294967301 (> 2^31)
?. b;                 ?. ' <- big64 expect 4294967301';
?. passf(b);          ?. ' <- passll(b) roundtrip expect 4294967301';
?. addf(b, 1);        ?. ' <- addll(b,1) expect 4294967302';

// 64-bit returns: args under 2^31, result returns full 64-bit (> 2^31)
?. addf(1000000000, 2000000000);   ?. ' <- addll(1e9,2e9) expect 3000000000';
?. addf(1000000000, -2000000000);  ?. ' <- addll(1e9,-2e9) expect -1000000000';

// 64-bit callback roundtrip (Fun function passes a C-supplied 64-bit value
// straight back; no 32-bit wrap on the FFI boundary)
fun pass(x)
  return x;
end fun;
var cbll = pass.@toCallback(nil, 'l:l');
?. applyllf(b, cbll); ?. ' <- applyll(big64, pass) roundtrip expect 4294967301';
