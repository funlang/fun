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
