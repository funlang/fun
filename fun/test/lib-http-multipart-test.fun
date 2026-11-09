// http-multipart: parser and req.multipart() checks. Snapshot is booleans.
// Only http-server is imported: req.multipart() must work without a separate
// http-multipart use; the wrapper loads the parser.
use 'fun/lib/http-server.fun';

var CRLF = 13.toChar() & 10.toChar();

fun mpPart(headers, data)
  result = headers & CRLF & CRLF & data;
end fun;

fun mpBody(boundary, parts)
  var out = '';
  var i = 0;
  while i < parts.@count() do
    out &= '--' & boundary & CRLF & parts[i] & CRLF;
    i += 1;
  end do;
  result = out & '--' & boundary & '--' & CRLF;
end fun;

fun mpErr(m, part)
  var e = m['error'];
  result = e <> nil and ('' & e).subpos(part) >= 0;
end fun;

fun mpEmpty(m)
  result = m['parts'].@count() = 0 and m['fields'].@count() = 0 and m['files'].@count() = 0;
end fun;

// --- basic fields and one file -------------------------------------------
var b1 = '----fun';
var body1 = mpBody(b1, [
  mpPart('Content-Disposition: form-data; name="user"', 'alice'),
  mpPart('Content-Disposition: form-data; name="note"', 'hi'),
  mpPart('Content-Disposition: form-data; name="avatar"; filename="a.txt"' & CRLF & 'Content-Type: text/plain', 'hello')
]);
var m1 = HttpMultipartParse(body1, 'multipart/form-data; boundary=' & b1);
?. m1['ok'];
?. m1['error'] = nil;
?. m1['parts'].@count() = 3;
?. m1['fields'].@count() = 2;
?. m1['files'].@count() = 1;
?. m1['fields']['user'][0] = 'alice';
?. m1['fields']['note'][0] = 'hi';
?. m1['files']['avatar'][0]['name'] = 'avatar';
?. m1['files']['avatar'][0]['filename'] = 'a.txt';
?. m1['files']['avatar'][0]['contentType'] = 'text/plain';
?. m1['files']['avatar'][0]['data'] = 'hello';
?. m1['parts'][2]['name'] = 'avatar';
?. m1['parts'][2]['data'] = 'hello';

// --- duplicate names, empty data, empty filename -------------------------
var b2 = 'b2';
var body2 = mpBody(b2, [
  mpPart('Content-Disposition: form-data; name="tag"', 'one'),
  mpPart('Content-Disposition: form-data; name="tag"', 'two'),
  mpPart('Content-Disposition: form-data; name="tag"', 'three'),
  mpPart('Content-Disposition: form-data; name="blank"', ''),
  mpPart('Content-Disposition: form-data; name="empty"; filename=""', ''),
  mpPart('Content-Disposition: form-data; name="doc"; filename="d1.txt"', 'd1'),
  mpPart('Content-Disposition: form-data; name="doc"; filename="d2.txt"', 'd2')
]);
var m2 = HttpMultipartParse(body2, 'multipart/form-data; boundary=' & b2);
?. m2['ok'];
?. m2['fields']['tag'].@count() = 3;
?. m2['fields']['tag'][0] = 'one';
?. m2['fields']['tag'][1] = 'two';
?. m2['fields']['tag'][2] = 'three';
?. m2['fields']['blank'][0].type() = 8;
?. m2['fields']['blank'][0].length() = 0;
?. m2['files']['empty'].@count() = 1;
?. m2['files']['empty'][0]['filename'].type() = 8;
?. m2['files']['empty'][0]['filename'].length() = 0;
?. m2['files']['empty'][0]['data'].type() = 8;
?. m2['files']['empty'][0]['data'].length() = 0;
?. m2['files']['doc'].@count() = 2;
?. m2['files']['doc'][0]['data'] = 'd1';
?. m2['files']['doc'][1]['data'] = 'd2';
?. m2['parts'].@count() = 7;

// --- Content-Type and boundary variants ----------------------------------
var b3 = 'a;b=c';
var m3 = HttpMultipartParse(mpBody(b3, [
  mpPart('Content-Disposition: form-data; name="x"', 'quoted')
]), 'Multipart/Form-Data; charset=utf-8; Boundary="' & b3 & '"');
?. m3['ok'];
?. m3['fields']['x'][0] = 'quoted';

var b4 = 'b=4';
var m4 = HttpMultipartParse(mpBody(b4, [
  mpPart('Content-Disposition: form-data; name="x"', 'eq')
]), 'multipart/form-data ; boundary = ' & b4);
?. m4['ok'];
?. m4['fields']['x'][0] = 'eq';

// --- preamble, epilogue, folded header, escaped filename -----------------
var b5 = 'b5';
var folded = 'Content-Disposition: form-data;' & CRLF
  & ' name="folded"; filename="a\"b.txt"' & CRLF
  & 'Content-Type: application/octet-stream' & CRLF
  & 'X-Test: one' & CRLF
  & 'X-Test: two' & CRLF
  & 'X-Url: http://example.test/a:b';
var body5 = 'preamble text' & CRLF & mpBody(b5, [mpPart(folded, 'filedata')]) & 'epilogue';
var m5 = HttpMultipartParse(body5, 'multipart/form-data; boundary=b5');
?. m5['ok'];
?. m5['parts'].@count() = 1;
?. m5['files']['folded'][0]['filename'] = 'a"b.txt';
?. m5['files']['folded'][0]['contentType'] = 'application/octet-stream';
?. m5['files']['folded'][0]['data'] = 'filedata';
?. m5['files']['folded'][0]['headers']['x-test'] = 'two';
?. m5['files']['folded'][0]['headers']['x-url'] = 'http://example.test/a:b';
?. m5['files']['folded'][0]['headers']['content-disposition'] <> nil;

// --- binary, CRLF and inline boundary-like text --------------------------
var b6 = 'b6';
var raw6 = 'A' & 0.toChar() & 'B' & CRLF & 'C--b6D' & CRLF;
var m6 = HttpMultipartParse(mpBody(b6, [
  mpPart('Content-Disposition: form-data; name="bin"; filename="b.bin"', raw6)
]), 'multipart/form-data; boundary=' & b6);
?. m6['ok'];
?. m6['files']['bin'][0]['data'].length() = raw6.length();
?. m6['files']['bin'][0]['data'] = raw6;
?. m6['files']['bin'][0]['contentType'] = 'text/plain';

var b10 = 'b10';
var raw10 = 'x' & CRLF & '--b10X' & CRLF & 'y';
var m10 = HttpMultipartParse(mpBody(b10, [
  mpPart('Content-Disposition: form-data; name="f"; filename="x"', raw10)
]), 'multipart/form-data; boundary=' & b10);
?. m10['ok'];
?. m10['files']['f'][0]['data'] = raw10;

var b11 = 'b11';
var raw11 = 'x' & CRLF & '--b11--X' & CRLF & 'y';
var m11 = HttpMultipartParse(mpBody(b11, [
  mpPart('Content-Disposition: form-data; name="f"; filename="x"', raw11)
]), 'multipart/form-data; boundary=' & b11);
?. m11['ok'];
?. m11['files']['f'][0]['data'] = raw11;

// empty body directly against the boundary (no extra framing CRLF)
var b12 = 'b12';
var body12 = '--' & b12 & CRLF & 'Content-Disposition: form-data; name="empty"' & CRLF & CRLF & '--' & b12 & '--' & CRLF;
var m12 = HttpMultipartParse(body12, 'multipart/form-data; boundary=' & b12);
?. m12['ok'];
?. m12['parts'].@count() = 1;
?. m12['fields']['empty'].@count() = 1;
?. m12['fields']['empty'][0].type() = 8;
?. m12['fields']['empty'][0].length() = 0;

var b13 = 'b13';
var body13 = '--' & b13 & CRLF & 'Content-Disposition: form-data; name="a"' & CRLF & CRLF
  & '--' & b13 & CRLF & 'Content-Disposition: form-data; name="b"' & CRLF & CRLF & 'v' & CRLF
  & '--' & b13 & '--' & CRLF;
var m13 = HttpMultipartParse(body13, 'multipart/form-data; boundary=' & b13);
?. m13['ok'];
?. m13['parts'].@count() = 2;
?. m13['fields']['a'].@count() = 1;
?. m13['fields']['a'][0].length() = 0;
?. m13['fields']['b'][0] = 'v';

// transport padding on part and closing boundary lines
var b14 = 'b14';
var body14 = '--' & b14 & ' ' & CRLF
  & 'Content-Disposition: form-data; name="a"' & CRLF & CRLF & 'v' & CRLF
  & '--' & b14 & 9.toChar() & CRLF
  & 'Content-Disposition: form-data; name="b"' & CRLF & CRLF & 'w' & CRLF
  & '--' & b14 & '--' & ' ' & 9.toChar() & CRLF;
var m14 = HttpMultipartParse(body14, 'multipart/form-data; boundary=' & b14);
?. m14['ok'];
?. m14['parts'].@count() = 2;
?. m14['fields']['a'][0] = 'v';
?. m14['fields']['b'][0] = 'w';

var b15 = 'b15';
var body15 = '--' & b15 & CRLF & 'Content-Disposition: form-data; name="a"' & CRLF & CRLF & 'v' & CRLF
  & '--' & b15 & ' --' & CRLF;
var m15 = HttpMultipartParse(body15, 'multipart/form-data; boundary=' & b15);
?. m15['ok'];
?. m15['parts'].@count() = 1;
?. m15['fields']['a'][0] = 'v';

var b16 = 'b16';
var body16 = '--' & b16 & CRLF & 'Content-Disposition: form-data; name="a"' & CRLF & CRLF & 'v' & CRLF
  & '--' & b16 & '--' & ' ' & 9.toChar();
var m16 = HttpMultipartParse(body16, 'multipart/form-data; boundary=' & b16);
?. m16['ok'];
?. m16['parts'].@count() = 1;
?. m16['fields']['a'][0] = 'v';

var b17 = 'b17';
var raw17 = 'x' & CRLF & '--b17 X' & CRLF & 'y';
var m17 = HttpMultipartParse(mpBody(b17, [
  mpPart('Content-Disposition: form-data; name="f"; filename="x"', raw17)
]), 'multipart/form-data; boundary=' & b17);
?. m17['ok'];
?. m17['files']['f'][0]['data'] = raw17;

// --- Unicode name and value ----------------------------------------------
var b7 = 'b7';
var m7 = HttpMultipartParse(mpBody(b7, [
  mpPart('Content-Disposition: form-data; name="名字"', '值')
]), 'multipart/form-data; boundary=' & b7);
?. m7['ok'];
?. m7['fields']['名字'][0] = '值';

// --- ordinary field vs file, default Content-Type ------------------------
var b8 = 'b8';
var m8 = HttpMultipartParse(mpBody(b8, [
  mpPart('Content-Disposition: form-data; name="plain"', 'field'),
  mpPart('Content-Disposition: form-data; name="typed"' & CRLF & 'Content-Type: text/plain; charset=utf-8', 'typed'),
  mpPart('Content-Disposition: form-data; name="file"; filename="x"', 'filed')
]), 'multipart/form-data; boundary=' & b8);
?. m8['ok'];
?. m8['fields']['plain'][0] = 'field';
?. m8['fields']['plain'] <> nil;
?. m8['fields']['typed'][0] = 'typed';
?. m8['files']['plain'] = nil;
?. m8['parts'][0]['contentType'] = 'text/plain';
?. m8['parts'][1]['contentType'] = 'text/plain; charset=utf-8';
?. m8['parts'][2]['contentType'] = 'text/plain';

// --- closing boundary only ------------------------------------------------
var m9 = HttpMultipartParse('--b9--' & CRLF, 'multipart/form-data; boundary=b9');
?. m9['ok'];
?. m9['parts'].@count() = 0;
?. m9['fields'].@count() = 0;
?. m9['files'].@count() = 0;

// --- malformed input: ok=false, empty results, readable error ------------
var me1 = HttpMultipartParse(body1, 'text/plain');
?. not me1['ok'];
?. mpEmpty(me1);
?. mpErr(me1, 'http-multipart:');
?. mpErr(me1, 'multipart/form-data');

var me2 = HttpMultipartParse(body1, 'multipart/form-data');
?. not me2['ok'];
?. mpEmpty(me2);
?. mpErr(me2, 'boundary');

var me3 = HttpMultipartParse('', 'multipart/form-data; boundary=x');
?. not me3['ok'];
?. mpEmpty(me3);
?. mpErr(me3, 'boundary not found');

var me4 = HttpMultipartParse('--x' & CRLF & 'Content-Disposition: form-data; name="a"' & CRLF & CRLF & 'v', 'multipart/form-data; boundary=x');
?. not me4['ok'];
?. mpEmpty(me4);
?. mpErr(me4, 'closing boundary');

var me5 = HttpMultipartParse('--x' & CRLF & 'Content-Disposition: form-data; name="a"' & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me5['ok'];
?. mpEmpty(me5);
?. mpErr(me5, 'header terminator');

var me6 = HttpMultipartParse('--x' & CRLF & 'Content-Disposition: attachment; name="a"' & CRLF & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me6['ok'];
?. mpEmpty(me6);
?. mpErr(me6, 'form-data');

var me7 = HttpMultipartParse('--x' & CRLF & 'Content-Disposition: form-data; filename="a"' & CRLF & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me7['ok'];
?. mpEmpty(me7);
?. mpErr(me7, 'name');

var me8 = HttpMultipartParse('--x' & CRLF & 'X-Test: y' & CRLF & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me8['ok'];
?. mpEmpty(me8);
?. mpErr(me8, 'Content-Disposition');

var me9 = HttpMultipartParse('--xX', 'multipart/form-data; boundary=x');
?. not me9['ok'];
?. mpEmpty(me9);
?. mpErr(me9, 'boundary not found');

var me10 = HttpMultipartParse('--x' & CRLF & ' X-Test: y' & CRLF & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me10['ok'];
?. mpEmpty(me10);
?. mpErr(me10, 'folded header');

var me11 = HttpMultipartParse('--x' & CRLF & 'NoColon' & CRLF & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me11['ok'];
?. mpEmpty(me11);
?. mpErr(me11, 'invalid header');

var me12 = HttpMultipartParse('--x' & CRLF & ': v' & CRLF & CRLF & 'v' & CRLF & '--x--' & CRLF, 'multipart/form-data; boundary=x');
?. not me12['ok'];
?. mpEmpty(me12);
?. mpErr(me12, 'header name');

var me13 = HttpMultipartParse(body1, nil);
?. not me13['ok'];
?. mpEmpty(me13);
?. mpErr(me13, 'Content-Type');

var me14 = HttpMultipartParse(body1, 7);
?. not me14['ok'];
?. mpEmpty(me14);
?. mpErr(me14, 'must be a string');

var me15 = HttpMultipartParse(7, 'multipart/form-data; boundary=x');
?. not me15['ok'];
?. mpEmpty(me15);
?. mpErr(me15, 'body');

var me17 = HttpMultipartParse('', 'multipart/form-data; boundary="a' & CRLF & 'b"');
?. not me17['ok'];
?. mpEmpty(me17);
?. mpErr(me17, 'invalid boundary');

var raised = false;
try
  var me16 = HttpMultipartParse('garbage', 'multipart/form-data; boundary=x');
except
  raised = true;
end try;
?. not raised;

// --- req.multipart() integration -----------------------------------------
var r = HttpReq();
r.body = body1;
r.headS = new [];
r.headS['content-type'] = 'multipart/form-data; boundary=' & b1;
var im = r.multipart();
?. im['ok'];
?. im['fields']['user'][0] = 'alice';
?. im['files']['avatar'][0]['data'] = 'hello';
im['fields']['user'][0] = 'changed';
?. r.multipart()['fields']['user'][0] = 'changed';

var r2 = HttpReq();
r2.body = body1;
r2.headS = new [];
var im2 = r2.multipart();
?. not im2['ok'];
?. mpErr(im2, 'Content-Type');

r.body = 'a=1&b=2';
r.headS['content-type'] = 'application/x-www-form-urlencoded';
?. r.form()['a'] = '1';
?. r.form()['b'] = '2';

// --- writer: basic fields, file and round-trip ---------------------------
var w1 = HttpMultipartWriter([boundary: 'fun-w1']);
?. w1.contentType() = 'multipart/form-data; boundary=fun-w1';
w1.field('user', 'alice');
w1.field('tag', 'one');
w1.field('tag', 'two');
w1.file('avatar', 'a.txt', 'hello', [contentType: 'text/plain']);
var wb1 = w1.body();
?. w1.body() = wb1;
?. wb1.substr(0, ('--fun-w1' & CRLF).length()) = '--fun-w1' & CRLF;
?. wb1.subpos('--fun-w1--' & CRLF) = wb1.length() - ('--fun-w1--' & CRLF).length();
var wm1 = HttpMultipartParse(wb1, w1.contentType());
?. wm1['ok'];
?. wm1['parts'].@count() = 4;
?. wm1['fields']['user'][0] = 'alice';
?. wm1['fields']['tag'].@count() = 2;
?. wm1['fields']['tag'][0] = 'one';
?. wm1['fields']['tag'][1] = 'two';
?. wm1['files']['avatar'][0]['filename'] = 'a.txt';
?. wm1['files']['avatar'][0]['contentType'] = 'text/plain';
?. wm1['files']['avatar'][0]['data'] = 'hello';
?. wm1['parts'][0]['contentType'] = 'text/plain';

// --- writer: file defaults, empty filename, empty writer -----------------
var w2 = HttpMultipartWriter([boundary: 'fun-w2']);
w2.file('f', 'x.bin', 'abc');
var wm2 = HttpMultipartParse(w2.body(), w2.contentType());
?. wm2['files']['f'][0]['contentType'] = 'application/octet-stream';

var w3 = HttpMultipartWriter([boundary: 'fun-w3']);
w3.file('empty', '', '');
var wb3 = w3.body();
?. wb3.subpos('filename=""') >= 0;
var wm3 = HttpMultipartParse(wb3, w3.contentType());
?. wm3['files']['empty'].@count() = 1;
?. wm3['files']['empty'][0]['filename'].type() = 8;
?. wm3['files']['empty'][0]['filename'].length() = 0;
?. wm3['files']['empty'][0]['data'].length() = 0;

var w4 = HttpMultipartWriter([boundary: 'fun-w4']);
var wb4 = w4.body();
?. wb4 = '--fun-w4--' & CRLF;
var wm4 = HttpMultipartParse(wb4, w4.contentType());
?. wm4['ok'];
?. wm4['parts'].@count() = 0;

// --- writer: binary, Unicode, embedded CRLF ------------------------------
var wbytes = '';
for i = 0 to 255 do wbytes &= i.toChar(); end do;
var w5 = HttpMultipartWriter([boundary: 'fun-w5']);
w5.field('bin', wbytes);
w5.file('blob', 'b.bin', wbytes);
var wm5 = HttpMultipartParse(w5.body(), w5.contentType());
?. wm5['fields']['bin'][0].length() = 256;
?. wm5['fields']['bin'][0].toByte(0) = 0;
?. wm5['fields']['bin'][0].toByte(255) = 255;
?. wm5['files']['blob'][0]['data'].length() = 256;
?. wm5['files']['blob'][0]['data'].toByte(128) = 128;

var w6 = HttpMultipartWriter([boundary: 'fun-w6']);
w6.field('名字', '张三');
w6.file('文件', '报告.txt', '内容');
var wm6 = HttpMultipartParse(w6.body(), w6.contentType());
?. wm6['fields']['名字'][0] = '张三';
?. wm6['files']['文件'][0]['filename'] = '报告.txt';
?. wm6['files']['文件'][0]['data'] = '内容';

var w7 = HttpMultipartWriter([boundary: 'fun-w7']);
w7.field('note', 'a' & CRLF & 'b' & CRLF & '--not-the-boundary');
w7.file('raw', 'r.txt', 'x' & CRLF & '--other' & CRLF & 'y');
var wm7 = HttpMultipartParse(w7.body(), w7.contentType());
?. wm7['fields']['note'][0] = 'a' & CRLF & 'b' & CRLF & '--not-the-boundary';
?. wm7['files']['raw'][0]['data'] = 'x' & CRLF & '--other' & CRLF & 'y';

// --- writer: quoted names and quoted boundary ----------------------------
var wbs = 92.toChar();
var wq = 34.toChar();
var w8 = HttpMultipartWriter([boundary: 'fun-w8']);
w8.field('a' & wq & 'b', 'v');
w8.file('c' & wbs & 'd', 'e' & wq & 'f.txt', 'x');
var wm8 = HttpMultipartParse(w8.body(), w8.contentType());
?. wm8['fields']['a' & wq & 'b'][0] = 'v';
?. wm8['files']['c' & wbs & 'd'][0]['filename'] = 'e' & wq & 'f.txt';

var w9 = HttpMultipartWriter([boundary: 'a b(c)']);
?. w9.contentType() = 'multipart/form-data; boundary="a b(c)"';
w9.field('x', 'y');
var wm9 = HttpMultipartParse(w9.body(), w9.contentType());
?. wm9['ok'];
?. wm9['fields']['x'][0] = 'y';

// --- writer: default boundary and locked boundary ------------------------
var wbp = 'multipart/form-data; boundary=';
var w10 = HttpMultipartWriter();
var wct10 = w10.contentType();
?. wct10.substr(0, wbp.length()) = wbp;
var wbnd = wct10.substr(wbp.length());
?. wbnd.substr(0, 4) = 'fun-';
?. wbnd.length() = 40;
w10.field('k', 'v');
var wb10 = w10.body();
?. wb10.substr(0, ('--' & wbnd & CRLF).length()) = '--' & wbnd & CRLF;
var wm10 = HttpMultipartParse(wb10, wct10);
?. wm10['ok'];
?. wm10['fields']['k'][0] = 'v';

var w11 = HttpMultipartWriter();
var wct11 = w11.contentType();
w11.field('k', 'v');
?. w11.contentType() = wct11;

// A boundary-looking prefix that is not a delimiter stays data.
var w12 = HttpMultipartWriter([boundary: 'hit']);
w12.field('a', '--hitz' & CRLF & 'ok');
w12.field('b', 'x' & CRLF & '--hitz' & CRLF & 'y');
var wm12 = HttpMultipartParse(w12.body(), w12.contentType());
?. wm12['ok'];
?. wm12['fields']['a'][0] = '--hitz' & CRLF & 'ok';
?. wm12['fields']['b'][0] = 'x' & CRLF & '--hitz' & CRLF & 'y';

// --- writer: invalid input raises ----------------------------------------
fun mpwRaise(fn)
  var bad = false;
  try
    fn();
  except
    bad = true;
  end try;
  result = bad;
end fun;

?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: 'bad' & wq & 'b']); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: 'a'.x(71)]); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: '']); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([nope: 1]); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter('x'); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.field('', 'v'); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.field('a' & CRLF, 'v'); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.field('a', 1); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.file('a', 1, 'x'); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.file('a', 'b', 1); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.file('a', 'b', 'c', [contentType: 'text/plain' & CRLF]); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.file('a', 'b', 'c', [nope: 1]); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter(); wx.field('a', 'b'); wx.body(); wx.field('c', 'd'); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: 'hit']); wx.field('a', 'x' & CRLF & '--hit' & CRLF); wx.body(); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: 'hit']); wx.field('a', '--hit' & CRLF); wx.body(); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: 'hit']); wx.field('a', 'x' & CRLF & '--hit'); wx.body(); }));
?. mpwRaise(((){ var wx = HttpMultipartWriter([boundary: 'hit']); wx.field('a', '--hit'); wx.body(); }));
