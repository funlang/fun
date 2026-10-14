// Builtin dispatch smoke test.
//
// The C-level builtins live in a per-library id table (CLbase/CLset in
// src/lib/libbase, libset) as "registered function pointer" values, and every
// call goes through one dispatch site (CLib.call). This test exercises a wide
// sample of those registered entries, so a broken registration (wrong function
// pointer width, wrong id, missing entry) shows up as a failing snapshot.
//
// md5/sha1 are covered by lib-hash-test.fun (they need the -dMD5 define).
?. ' a b '.escape();
?. 'Hello'.lower();
?. 'Hello'.upper();
?. 'abcdef'.substr(1, 3);
?. 'abcdef'.subpos('cd');
?. 'abc'.length();
?. 'ab'.x(3);
?. 65.toChar();
?. 'A'.toByte();
?. 1.5.toStr();
?. '12'.toNum() + 1;

// strict compare / logical type id (basic values)
// type(): stable ids anchored to COM VARENUM (VT_*), portability-normalized
?. nil.type();       // 0  VT_EMPTY
?. 1.type();         // 3  VT_I4
?. 1.5.type();       // 5  VT_R8
?. 'abc'.type();     // 8  VT_BSTR
?. true.type();      // 11 VT_BOOL
?. @"2010-04-09 15:35:15".type(); // 7 VT_DATE
// eq(): strict, no coercion (the loose '=' treats these as equal)
?. nil.eq(0);        // false
?. nil.eq('');       // false
?. 0.eq(false);      // false
?. '1'.eq(1);        // false
?. 1.eq(1.0);        // false
?. 'ABC'.eq('abc');  // false
// eq(): true when type and value match
?. 1.eq(1);          // true
?. 'abc'.eq('abc');  // true
?. nil.eq(nil);      // true
?. true.eq(true);    // true
?. 2.eq(1 + 1);      // true

// math builtins
?. 1.exp() > 2;
?. 1.log() < 0.1;
?. 0.sin();
?. 0.cos();
?. 1.atan() > 0.7;
?. 5.random() < 5;

// regex builtins
?. 'abcdef'.toRegex('i') != nil;
?. 'abcdef'.match(/cd/) != nil;
?. 'abcdef'.replace(/cd/, 'XY');
?. 'a1b2'.replace(/\d/, '#', all: true);

// file builtins (fixed paths under /tmp; overwritten on every run)
'/tmp/fun-builtin-dispatch.txt'.save('probe');
?. '/tmp/fun-builtin-dispatch.txt'.load();
?. '/tmp/fun-builtin-dispatch.txt'.size();
'/tmp/fun-builtin-dispatch.txt'.copy('/tmp/fun-builtin-dispatch-copy.txt');
?. '/tmp/fun-builtin-dispatch-copy.txt'.load();

// set builtins
var st = new [10, 20, 30];
?. st.@count();
?. st.@toJson();
var cl = st.@clone();
?. cl.@count();
st.@add(40);
?. st.@count();

// @has: key presence, distinct from a nil value and from `in` (which scans
// values). A numeric key addresses a list slot, any other key names a member.
var mp = new [];
mp['a'] = 1;
mp['b'] = nil;
?. mp.@has('a');   // true
?. mp.@has('b');   // true  (present, value is nil)
?. mp.@has('c');   // false
?. mp['b'] = nil;  // true  (still ambiguous: absent and nil both yield nil)
?. st.@has(0);     // true
?. st.@has(3);     // true  (40 was added)
?. st.@has(4);     // false
?. st.@has(-1);    // true
?. st.@has('x');   // false

// host facts: os/cpu/compiler are machine-specific, so assert the invariant
// shape instead of printing the raw value (keeps the snapshot host-neutral).
var hf = 'host'.arg().getJson(fd: true);
?. hf.os <> '';         // 'linux' / 'macos' / 'windows'
?. hf.cpu <> '';        // 'x86_64' / 'aarch64' / ...
?. hf.bits;             // 64 on every supported target
?. hf.chars;            // 1
?. hf.version >= 20250000;

