// Bounds safety checks for the string and list index / byte-access paths.
//
// These used to read or write past the buffer (silent garbage, heap or string
// header corruption). Now out-of-range writes raise and reads yield a safe
// default. Every assertion prints a boolean, so the snapshot is stable.
//
//   1  string index read: negative wraps, out of range is nil
//   2  string index write: out of range raises, in range works
//   3  byte access: toByte out of range is 0, fromByte out of range raises
//   4  list: @count out of range raises / resizes safely (a huge *positive*
//      index is allocation-dependent, so it is not asserted - see section 4)
//   5  movs: out-of-range raises, in-range copies
//   6  x(n): reverse/sort still work

var threw = false;

//--------------------------------------------------------------
// 1. string index read
//--------------------------------------------------------------
var s = 'abc';
?. 'read neg wraps: ' & (s[-1] = 'c');
?. 'read far is nil: ' & (s[10] = nil);
?. 'read far neg is nil: ' & (s[-10] = nil);
// float index selects a byte of char i+1 (platform-independent bounds only)
?. 'float idx in range: ' & (s[1.5] <> nil);
?. 'float idx oob is nil: ' & (s[3.5] = nil);

//--------------------------------------------------------------
// 2. string index write
//--------------------------------------------------------------
var t = 'abc';
try t[10] = 'X'; except threw = true; end try;
?. 'write oob raises: ' & threw;
threw = false;
var t2 = 'abc';
try t2[-10] = 'X'; except threw = true; end try;
?. 'write far neg raises: ' & threw;
var t3 = 'abc';
t3[0] = 'X';
?. 'write in range: ' & (t3 = 'Xbc');

//--------------------------------------------------------------
// 3. byte access
//--------------------------------------------------------------
var e = 'abc';
?. 'toByte oob is 0: ' & (e.toByte(10) = 0);
?. 'toByte neg is 0: ' & (e.toByte(-1) = 0);
?. 'toByte in range: ' & (e.toByte(1) = 98);
var f = 'abc';
threw = false;
try f.fromByte(5, 65); except threw = true; end try;
?. 'fromByte oob raises: ' & threw;

//--------------------------------------------------------------
// 4. list count / index
//--------------------------------------------------------------
var l = new [1, 2, 3];
threw = false;
try l.@count(-5); except threw = true; end try;
?. 'count negative raises: ' & threw;
var l2 = new [1, 2, 3];
l2.@count(5);
?. 'count grows safely: ' & (l2.@count() = 5 and l2[4] = nil);
// A huge positive list index grows the backing array. That raises EOutOfMemory
// on Linux (the allocation fails) but can succeed lazily on macOS, so it is not
// a portable assertion (no upper size cap, by author decision 2026-09-14; see
// art/notes/safety-bounds.md). The deterministic bounds are the far-negative
// write below and the sparse map just after it.
var l4 = new [1, 2, 3];
threw = false;
try l4[-1000] = 7; except threw = true; end try;
?. 'far neg index raises: ' & threw;
var l5 = new [];
l5[19970] = 5;   // sparse integer-keyed map (lib-unicode-lnx uses this)
?. 'sparse map works: ' & (l5[19970] = 5 and l5.@count() = 19971);

//--------------------------------------------------------------
// 5. movs
//--------------------------------------------------------------
var g = 'abc';
var h = '....';
threw = false;
try g.movs(dest: h, pos: 10); except threw = true; end try;
?. 'movs oob raises: ' & threw;
var g2 = 'abc';
var h2 = '....';
?. 'movs in range: ' & (g2.movs(dest: h2, len: 3) = 3 and h2 = 'abc.');

//--------------------------------------------------------------
// 6. x(n)
//--------------------------------------------------------------
var k = 'cba';
?. 'x(-1) reverse: ' & (k.x(-1) = 'abc');
?. 'x(-2) sort: ' & (k.x(-2) = 'abc');
?. 'x(2) replicate: ' & (k.x(2) = 'cbacba');

?. 'done';
