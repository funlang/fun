// csv: streaming reader/writer. The snapshot contains booleans only.
use 'fun/lib/csv.fun';
use 'fun/lib/fs.fun';
use 'fun/lib/lib-path.fun';

var nl = 10.toChar();
var crlf = 13.toChar() & nl;
var q = '"';
var apos = 39.toChar();
var bom = 239.toChar() & 187.toChar() & 191.toChar();

class _StrReader(s, n)
  var data = s;
  var sz = n;
  var pos = 0;
  fun read(k)
    if pos >= data.length() then result = ''; return; end if;
    var m = sz;
    if k < m then m = k; end if;
    var e = pos + m;
    if e > data.length() then e = data.length(); end if;
    result = data.substr(pos, e - pos);
    pos = e;
  end fun;
end class;

class _StrWriter()
  var text = '';
  fun write(s)
    text &= s;
  end fun;
end class;

fun _r1(a)
  result = new [];
  result.@add(a);
end fun;

fun _r2(a, b)
  result = new [];
  result.@add(a);
  result.@add(b);
end fun;

fun _r3(a, b, c)
  result = new [];
  result.@add(a);
  result.@add(b);
  result.@add(c);
end fun;

fun _collect(r)
  var rows = new [];
  loop
    var row = r.read();
    exit when row = nil;
    rows.@add(row);
  end loop;
  result = rows;
end fun;

fun _rows(s, opts, sz)
  var f = _StrReader(s, sz or 8192);
  result = _collect(csv.reader(f, opts));
end fun;

fun _text(rows, opts)
  var w = _StrWriter();
  var c = csv.writer(w, opts);
  for i = 0 to rows.@count() - 1 do c.write(rows[i]); end do;
  result = w.text;
end fun;

fun _fails(s, opts, sz)
  var failed = false;
  try
    _rows(s, opts, sz);
  except
    failed = true;
  end try;
  result = failed;
end fun;

fun _errHas(s, opts, sz, needle)
  var found = false;
  try
    _rows(s, opts, sz);
  except
    found = ('' & @).subpos(needle) >= 0;
  end try;
  result = found;
end fun;

// basic rows / trailing newline
var rows = _rows('a,b' & nl & '1,2' & nl, nil, 8192);
?. rows.@count() = 2;
?. rows[0][0] = 'a';
?. rows[0][1] = 'b';
?. rows[1][0] = '1';
?. rows[1][1] = '2';

// no trailing newline
rows = _rows('a,b' & nl & '1,2', nil, 8192);
?. rows.@count() = 2;
?. rows[1][1] = '2';

// one-character numeric text at a chunk boundary is not EOF
rows = _rows('0' & nl, nil, 1);
?. rows[0][0] = '0';

// CRLF and empty fields
rows = _rows('a,,c' & crlf & ',,' & crlf, nil, 8192);
?. rows.@count() = 2;
?. rows[0].@count() = 3;
?. rows[0][1] = '';
?. rows[1].@count() = 3;
?. rows[1][0] = '';
?. rows[1][2] = '';

// quoted fields
rows = _rows(q & 'a,b' & q & ',' & q & 'x' & q & q & 'y' & q & nl, nil, 8192);
?. rows[0][0] = 'a,b';
?. rows[0][1] = 'x' & q & 'y';

// empty quoted field
rows = _rows(q & q & nl, nil, 8192);
?. rows[0].@count() = 1;
?. rows[0][0] = '';

// quoted multiline
rows = _rows(q & 'a' & nl & 'b' & q & nl, nil, 8192);
?. rows[0][0] = 'a' & nl & 'b';
rows = _rows(q & 'a' & crlf & 'b' & q & nl, nil, 8192);
?. rows[0][0] = 'a' & crlf & 'b';
rows = _rows(q & 'a' & crlf & 'b' & q & nl, nil, 1);
?. rows[0][0] = 'a' & crlf & 'b';

// long unquoted field split across many reads
var bigField = 'x'.x(20000);
rows = _rows(bigField & nl, nil, 7);
?. rows[0][0].length() = 20000;
?. rows[0][0] = bigField;

// blank line: keep as [''] in one column
rows = _rows('a' & nl & nl & 'b' & nl, nil, 8192);
?. rows.@count() = 3;
?. rows[1].@count() = 1;
?. rows[1][0] = '';

// blank line: skipped
rows = _rows('a' & nl & nl & 'b' & nl, [skipEmptyLines: true], 8192);
?. rows.@count() = 2;
?. rows[1][0] = 'b';

// blank line in a multi-column file errors by default
?. _fails('a,b' & nl & nl & '1,2' & nl, nil, 8192);
?. _errHas('a,b' & nl & nl, nil, 8192, 'line 2');
?. _errHas('a,b' & nl & nl, nil, 8192, 'expected 2');
?. (not _fails('a,b' & nl & nl & '1,2' & nl, [skipEmptyLines: true], 8192));
?. _fails('a,b' & crlf & crlf & '1,2' & crlf, nil, 2);
?. (not _fails('a,b' & crlf & crlf & '1,2' & crlf, [skipEmptyLines: true], 2));

// whitespace-only line is data, not blank
rows = _rows('a' & nl & '   ' & nl, nil, 8192);
?. rows.@count() = 2;
?. rows[1][0] = '   ';

// column count is strict
?. _fails('a,b' & nl & '1' & nl, nil, 8192);
?. _errHas('a,b' & nl & '1' & nl, nil, 8192, 'expected 2');
?. _errHas('a,b' & crlf & '1' & crlf, nil, 1, 'line 2');
?. _errHas('a,b' & nl & nl & '1' & nl, [skipEmptyLines: true], 1, 'line 3');
?. _fails('a' & nl & '1,2' & nl, nil, 8192);
?. _rows(nl & nl & nl, [skipEmptyLines: true], 1).@count() = 0;

// malformed quoting
?. _fails('a"b' & nl, nil, 8192);
?. _fails('ab' & q & nl, nil, 2);
?. _fails(q & 'a' & nl, nil, 8192);
?. _errHas(q & 'a' & nl, nil, 8192, 'unterminated');
?. _fails(q & 'a' & q & 'x' & nl, nil, 8192);
?. _fails('a' & 13.toChar() & 'b' & nl, nil, 8192);
?. _errHas('a' & 13.toChar() & 'b' & nl, nil, 8192, 'bare CR');

// options
rows = _rows(apos & 'a;b' & apos & ';c' & nl, [delimiter: ';', quote: apos], 8192);
?. rows[0][0] = 'a;b';
?. rows[0][1] = 'c';
?. _fails('a' & nl, [delimiter: ''], 8192);
?. _fails('a' & nl, [delimiter: 'ab'], 8192);
?. _fails('a' & nl, [delimiter: 200.toChar()], 8192);
?. _fails('a' & nl, [delimiter: ',', quote: ','], 8192);
?. _fails('a' & nl, [skipEmptyLines: 'yes'], 8192);
?. _rows('a,b' & nl, [crlf: true], 1)[0].@count() = 2;

// BOM, including chunk boundaries
rows = _rows(bom & 'a,b' & nl, nil, 8192);
?. rows[0][0] = 'a';
rows = _rows(bom & q & 'a' & q & nl, nil, 1);
?. rows[0][0] = 'a';
rows = _rows(bom & nl & 'a' & nl, [skipEmptyLines: true], 1);
?. rows.@count() = 1;
?. rows[0][0] = 'a';
for z = 1 to 4 do
  rows = _rows(bom & 'a,b' & crlf & '1,2' & nl, nil, z);
  ?. rows.@count() = 2;
  ?. rows[0][1] = 'b';
end do;

// every byte size around block boundaries
var data = q & 'a,b' & q & ',' & q & 'x' & q & q & 'y' & q & crlf & '1,2' & nl;
for z = 1 to 6 do
  rows = _rows(data, nil, z);
  ?. rows.@count() = 2;
  ?. rows[0][0] = 'a,b';
  ?. rows[0][1] = 'x' & q & 'y';
end do;

// EOF behavior
var r = csv.reader(_StrReader('a' & nl, 1));
?. r.read()[0] = 'a';
?. r.read() = nil;
?. r.read() = nil;
?. _rows('', nil, 1).@count() = 0;
?. _rows(bom, nil, 1).@count() = 0;
?. _rows('a,', nil, 1)[0].@count() = 2;
?. _rows(q & 'a' & q, nil, 1)[0][0] = 'a';
?. _fails(q & 'a', nil, 1);

// writer quoting / scalar conversion / line endings
rows = new [];
rows.@add(_r3('a', 'b,c', 'x' & q & 'y'));
?. _text(rows, nil) = 'a,"b,c","x""y"' & nl;
rows = new [];
rows.@add(_r3('  sp', nil, 12));
?. _text(rows, nil) = '"  sp",,12' & nl;
rows = new [];
rows.@add(_r3(1.5, true, 'z'));
?. _text(rows, nil) = '1.5,True,z' & nl;
rows = new [];
rows.@add(_r1(0));
?. _text(rows, nil) = '0' & nl;
rows = new [];
rows.@add(_r1('0.0'));
?. _text(rows, nil) = '0.0' & nl;
rows = new [];
rows.@add(_r3('a', 'b', 'c'));
?. _text(rows, [crlf: true]) = 'a,b,c' & crlf;

// empty row and single empty field both serialize as a blank line
rows = new [];
rows.@add(new []);
?. _text(rows, nil) = nl;
rows = new [];
rows.@add(_r1(''));
?. _text(rows, nil) = nl;
rows = new [];
rows.@add(new []);
?. _text(rows, [crlf: true]) = crlf;
rows = new [];
rows.@add(_r1(''));
?. _text(rows, [crlf: true]) = crlf;
rows = new [];
rows.@add(_r2('a', 'b'));
?. _text(rows, [skipEmptyLines: true]) = 'a,b' & nl;

// writer rejects non-scalar fields
var bad = false;
try
  rows = new [];
  var cell = new [];
  rows.@add(_r1(cell));
  _text(rows, nil);
except
  bad = true;
end try;
?. bad;

// writer rejects non-indexable rows
bad = false;
try
  var w = _StrWriter();
  var c = csv.writer(w, nil);
  c.write(nil);
except
  bad = true;
end try;
?. bad;

// round-trip
rows = new [];
rows.@add(_r3('a', 'b,c', 'x' & q & 'y'));
rows.@add(_r3('  sp', '', 'line' & nl & 'break'));
var text = _text(rows, nil);
var back = _rows(text, nil, 1);
?. back.@count() = 2;
?. back[0][1] = 'b,c';
?. back[1][2] = 'line' & nl & 'break';

// writer options
rows = new [];
rows.@add(_r2('a;b', 'c'));
?. _text(rows, [delimiter: ';']) = '"a;b";c' & nl;
rows = new [];
rows.@add(_r2('a' & apos & 'b', 'c'));
?. _text(rows, [quote: apos]) = apos & 'a' & apos & apos & 'b' & apos & ',c' & nl;

// alphabetic quote must not match case-insensitively
var qx = 'x';
rows = new [];
rows.@add(_r1('a,Xb,c'));
var tx = _text(rows, [quote: qx]);
?. tx = qx & 'a,Xb,c' & qx & nl;
?. _rows(tx, [quote: qx], 1)[0][0] = 'a,Xb,c';
rows = new [];
rows.@add(_r1('a,xXb,c'));
tx = _text(rows, [quote: qx]);
?. tx = qx & 'a,' & qx & qx & 'Xb,c' & qx & nl;
?. _rows(tx, [quote: qx], 1)[0][0] = 'a,xXb,c';

// fs handle integration
var root = fs.tempDir('fun-csv-test-');
var p = PathJoin([root, 'data.csv']);
var f = fs.open(p, 'w');
var cw = csv.writer(f);
for i = 0 to 9999 do
  cw.write(_r3('row-' & i, i, 'value,' & i));
end do;
f.close();
var g = fs.open(p, 'r');
var cr = csv.reader(g);
var n = 0;
var first = nil;
var last = nil;
loop
  var row = cr.read();
  exit when row = nil;
  if n = 0 then first = row; end if;
  last = row;
  n += 1;
end loop;
?. n = 10000;
?. first[0] = 'row-0';
?. last[0] = 'row-9999';
?. last[2] = 'value,9999';
g.close();

var zp = PathJoin([root, 'zero.csv']);
var zf = fs.open(zp, 'w');
var zw = csv.writer(zf);
zw.write([0]);
zw.write(['00']);
zf.close();
?. zp.load() = '0' & nl & '00' & nl;

?. fs.removeAll(root);
?. fs.exists(root) = false;
