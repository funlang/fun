use 'fun/lib/lib-host.fun';

// libffitest is built per host by fun/test/ffi/build.sh (the runner builds
// it on demand): .so on Linux, .dylib on macOS.
var FFITEST = DyLib('./fun/test/ffi/libffitest.so', './fun/test/ffi/libffitest.dylib');

########################################
# Unix FFI (Linux / macOS): float and mixed double/int args
########################################
# Float args/returns use ffi_type_float (SSE single-precision).
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-float.fun
########################################

var fsumf  = FFITEST.getapi('fsum', 'ff:f');
var fdblf  = FFITEST.getapi('fdbl', 'f:f');
var dfromf = FFITEST.getapi('dfromf', 'f:d');
var mixsum = FFITEST.getapi('mixsum', 'idi:d');
var fivef  = FFITEST.getapi('five', ':d');
var identf = FFITEST.getapi('ident', 'd:d');

?. fsumf(1.5, 2.25); ?. ' <- fsum(1.5,2.25) expect 3.75';
?. fdblf(2.5);       ?. ' <- fdbl(2.5) expect 5';
?. dfromf(3.0);      ?. ' <- dfromf(3) double-from-float expect 6';
?. mixsum(2, 1.5, 3); ?. ' <- mixsum(2,1.5,3) expect 6.5';
?. fivef();          ?. ' <- five() expect 5';
?. identf(7.5);      ?. ' <- ident(7.5) expect 7.5';
