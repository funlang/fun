use 'fun/lib/lib-host.fun';

// A bare `var x` passed for a 'p' parameter is an OUT/INOUT pointer, the same
// convention win32's winapi.pas has always had. The lffi backend passes the
// address of a pointer-width scratch cell and copies the result back. An
// explicit lffi buffer address keeps working unchanged, and a NULL stays NULL.
var FFITEST = DyLibWin('./fun/test/ffi/libffitest.so', './fun/test/ffi/libffitest.dylib',
                       './fun/test/ffi/libffitest.dll');

var setout = FFITEST.getapi('setout', 'pii:i');
var addout = FFITEST.getapi('addout', 'pii:i');

var h = 0;
?. setout(var h, 42);
?. h;
?. addout(var h, 8);
?. h;

var buf = 0.toChar().x(8);
?. setout(buf.toNum(-1), 7);
?. buf.toByte(0);

?. setout(0, 9);
