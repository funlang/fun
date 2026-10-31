// Functional checks for portable libraries (not just "does it load").
//
// lib-loadcheck.sh only proves a module can be `use`d; these are real
// behavioural checks on modules that must work on every host. Bit-level work
// (SHA-256, base64 packing) is exactly where 64-bit porting bugs hide, so the
// expected values here are the published test vectors.
use 'fun/lib/lib-base64.fun';
use 'fun/lib/lib-md5.fun';

//--- base64: round trip + hex form ---
?. Str2Base64('hello');
?. fromBase64('aGVsbG8=');
?. Hex2Base64('414243');            // base64 of "ABC"
?. fromBase64(Str2Base64('Fun 语言'));

//--- SHA-256 known vectors (libcrypto fast path, or the pure-Fun fallback) ---
?. SHA256('abc');
?. SHA256('');
?. SHA256('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq');
// multi-block vectors: these catch the pure-Fun state not wrapping at 32 bits
// (wrong digest from 120 bytes up) and the lib-crypt alias falling out of scope.
?. SHA256('a'.x(120));
?. SHA256('a'.x(1000));

//--- regex engine: named groups and (?J) duplicate names must work ---
var m = 'b'.match(/(?J)(?P<x>a)|(?P<x>b)/);
?. m.@('x');
var n = '2026-09'.match(/(?P<y>\d++)\D++(?P<mo>\d++)/);
?. n.@('y');
?. n.@('mo');
