use 'fun/lib/lib-host.fun';

// libffitest is built per host by fun/test/ffi/build.sh (the runner builds
// it on demand): .so on Linux, .dylib on macOS.
var FFITEST = DyLib('./fun/test/ffi/libffitest.so', './fun/test/ffi/libffitest.dylib');

########################################
# Unix FFI (Linux / macOS): plain scalar calls via getapi
########################################
# Exercises src/lib/lffi.pas basic getapi() path against libc/libm and the
# local helper libffitest.so. Expected outputs are shown on each line.
# Run from the repo root:
#   src/prj/fun/funcmd fun/test/ffi/ffi-scalar.fun
########################################

// ---- libc ----
var getpid = LibC().getapi('getpid', ':i');
?. getpid();          ?. ' <- getpid() real pid (varies)';

var strlen = LibC().getapi('strlen', 's:i');
?. strlen('hello world'); ?. ' <- strlen("hello world") expect 11';

var atoi = LibC().getapi('atoi', 's:i');
?. atoi('1234');       ?. ' <- atoi("1234") expect 1234';

var getenv = LibC().getapi('getenv', 's:s');
?. getenv('HOME');     ?. ' <- getenv("HOME") (string return)';

// ---- libm (double args + return, SSE) ----
var pow = DyLib('libm.so.6', 'libSystem.B.dylib').getapi('pow', 'dd:d');
?. pow(2.0, 10.0);     ?. ' <- pow(2,10) expect 1024';

var sinf = DyLib('libm.so.6', 'libSystem.B.dylib').getapi('sin', 'd:d');
?. sinf(3.141592653589793 / 2); ?. ' <- sin(pi/2) expect 1';

// ---- helper lib: double/int returns ----
var summ  = FFITEST.getapi('summ', 'dd:d');
?. summ(2.0, 3.0);     ?. ' <- summ(2,3) expect 5';

var addi  = FFITEST.getapi('addi', 'ii:i');
?. addi(20, 22);       ?. ' <- addi(20,22) expect 42';
