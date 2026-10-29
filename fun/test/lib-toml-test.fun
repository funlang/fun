// toml: document reader/writer. The snapshot contains booleans only.
use 'fun/lib/io.fun';
use 'fun/lib/toml.fun';
use 'fun/lib/fs.fun';
use 'fun/lib/lib-path.fun';

var nl = 10.toChar();
var cr = 13.toChar();
var q = 34.toChar();
var sq = 39.toChar();
var bs = 92.toChar();
var bom = 239.toChar() & 187.toChar() & 191.toChar();

class _ShortReader(s, sz)
  var data = s;
  var sz = sz;
  var pos = 0;
  fun read(n)
    if pos >= data.length() then result = ''; return; end if;
    var m = sz;
    if n < m then m = n; end if;
    var e = pos + m;
    if e > data.length() then e = data.length(); end if;
    result = data.substr(pos, e - pos);
    pos = e;
  end fun;
end class;

fun _parse(s)
  result = toml.reader(io.buffer(s)).read();
end fun;

fun _text(doc, opts)
  var b = io.buffer();
  toml.writer(b, opts).write(doc);
  result = b.text();
end fun;

fun _bad(s)
  var failed = false;
  try
    _parse(s);
  except
    failed = true;
  end try;
  result = failed;
end fun;

fun _errHas(s, needle)
  var found = false;
  try
    _parse(s);
  except
    found = ('' & @).subpos(needle) >= 0;
  end try;
  result = found;
end fun;

// empty document and one-shot reader
var r = toml.reader(io.buffer(''));
?. r.read().@count() = 0;
?. r.read() = nil;
?. _text(_parse('')) = '';

// short reads are allowed
var rs = _ShortReader('a = 1' & nl & '[s]' & nl & 'b = 2' & nl, 1);
var rd = toml.reader(rs);
?. rd.read()['s']['b'] = 2;
?. rd.read() = nil;
?. _text(_parse('a = 1' & nl & 'b = true' & nl)) = 'a = 1' & nl & 'b = true' & nl;
?. _text(_parse('a = []' & nl)) = 'a = []' & nl;

// basic scalar values
var d = _parse('title = "TOML"' & nl & 'count = 42' & nl &
               'ratio = 3.5' & nl & 'ok = true' & nl & 'no = false' & nl);
?. d['title'] = 'TOML';
?. d['count'] = 42;
?. d['ratio'] = 3.5;
?. d['ok'] = true;
?. d['no'] = false;

// comments, whitespace, BOM and CRLF
d = _parse(bom & ' # comment' & cr & nl & 'a = 1 # tail' & cr & nl &
           '[s]' & cr & nl & ' b = 2 ' & cr & nl);
?. d['a'] = 1;
?. d['s']['b'] = 2;

// strings and escapes
d = _parse('a = "one' & bs & 'ttwo' & bs & 'u0041"' & nl &
           'b = ' & q & q & q & nl & 'multi' & nl & 'line' & q & q & q & nl &
           'c = ' & sq & 'raw' & bs & 'n' & sq & nl &
           'd = ' & sq & sq & sq & nl & 'raw' & nl & sq & sq & sq & nl);
?. d['a'] = 'one' & 9.toChar() & 'twoA';
?. d['b'] = 'multi' & nl & 'line';
?. d['c'] = 'raw' & bs & 'n';
?. d['d'] = 'raw' & nl;
d = _parse('d = ' & q & q & q & nl & 'one' & bs & '   ' & nl & '  two' & nl & q & q & q & nl);
?. d['d'] = 'onetwo' & nl;

// numbers and special floats
d = _parse('a = -42' & nl & 'b = 0x10' & nl & 'c = 0o10' & nl &
           'd = 0b101' & nl & 'e = 1_000' & nl & 'f = 1.5' & nl &
           'g = 1e3' & nl & 'h = inf' & nl & 'i = nan' & nl);
?. d['a'] = -42;
?. d['b'] = 16;
?. d['c'] = 8;
?. d['d'] = 5;
?. d['e'] = 1000;
?. d['f'] = 1.5;
?. d['g'] = 1000;
?. d['h'].tomlKind() = 'float';
?. d['h'].text = 'inf';
?. d['i'].text = 'nan';

// dates and times keep their source form
d = _parse('odt = 1979-05-27T07:32:00Z' & nl &
           'ldt = 1979-05-27 07:32:00' & nl &
           'day = 1979-05-27' & nl & 'clock = 07:32:00' & nl);
?. d['odt'].tomlKind() = 'offset-datetime';
?. d['odt'].text = '1979-05-27T07:32:00Z';
?. d['ldt'].tomlKind() = 'local-datetime';
?. d['day'].tomlKind() = 'date';
?. d['clock'].tomlKind() = 'time';

// arrays: multiline, comments, trailing comma and nesting
d = _parse('a = [' & nl & '  1, # one' & nl & '  2,' & nl & ']' & nl &
           'b = [[1, 2], [3]]' & nl);
?. d['a'].@count() = 2;
?. d['a'][1] = 2;
?. d['b'][0][1] = 2;
?. d['b'][1][0] = 3;

// inline tables / dotted keys / quoted keys
d = _parse('a = { x = 1, y = [2, 3] }' & nl &
           'user.name = "n"' & nl & 'user.age = 7' & nl &
           q & 'x.y' & q & ' = 4' & nl);
?. d['a']['x'] = 1;
?. d['a']['y'][1] = 3;
?. d['user']['name'] = 'n';
?. d['user']['age'] = 7;
?. d['x.y'] = 4;

// tables and arrays of tables
d = _parse('[server]' & nl & 'host = "localhost"' & nl &
           '[server.tls]' & nl & 'enabled = true' & nl &
           '[[users]]' & nl & 'name = "a"' & nl &
           '[[users]]' & nl & 'name = "b"' & nl);
?. d['server']['host'] = 'localhost';
?. d['server']['tls']['enabled'] = true;
?. d['users'].@count() = 2;
?. d['users'][1]['name'] = 'b';

// nested tables under array tables
d = _parse('[[products]]' & nl & 'name = "a"' & nl &
           '[products.details]' & nl & 'x = 1' & nl &
           '[[products]]' & nl & 'name = "b"' & nl &
           '[products.details]' & nl & 'x = 2' & nl);
?. d['products'][0]['details']['x'] = 1;
?. d['products'][1]['details']['x'] = 2;
var np = _parse(_text(d));
?. np['products'][1]['details']['x'] = 2;

// writer round-trip
d = _parse('title = "TOML"' & nl & 'n = 42' & nl & 'ok = true' & nl &
           'f = 1e3' & nl & 'nums = [1, 2]' & nl &
           '[server]' & nl & 'host = "localhost"' & nl &
           '[[users]]' & nl & 'name = "a"' & nl &
           '[[users]]' & nl & 'name = "b"' & nl);
var t = _text(d);
?. t.subpos('ok = true') >= 0;
?. t.subpos('f = 1000.0') >= 0;
?. t.subpos('[server]') >= 0;
?. t.subpos('[[users]]') >= 0;
var d2 = _parse(t);
?. d2['title'] = 'TOML';
?. d2['f'] = 1000;
?. d2['server']['host'] = 'localhost';
?. d2['users'].@count() = 2;
?. d2['users'][1]['name'] = 'b';

// writer CRLF and one-shot writer
var b = io.buffer();
toml.writer(b, [crlf: true]).write(_parse('a = 1' & nl));
?. b.text().subpos(cr & nl) >= 0;
var wb = io.buffer();
var w = toml.writer(wb);
w.write(_parse('a = 1' & nl));
var wrote = false;
try
  w.write(_parse('b = 2' & nl));
except
  wrote = true;
end try;
?. wrote;
var rootBad = false;
try
  toml.writer(io.buffer()).write('x');
except
  rootBad = true;
end try;
?. rootBad;
?. _text(_parse('d = 1979-05-27T07:32:00Z' & nl)) = 'd = 1979-05-27T07:32:00Z' & nl;
?. _bad('a = 1' & nl & 'a = 2' & nl);
?. _errHas('[a]' & nl & '[a]' & nl, 'duplicate table');
?. _errHas('[[a]]' & nl & '[a]' & nl, 'conflicts');
?. _errHas('a = 1' & nl & '[a]' & nl, 'conflicts');
?. _errHas('a = 1979-99-99' & nl, 'invalid date');
?. _errHas('a = "x' & nl, 'newline');
?. _errHas('a = [1, 2' & nl, 'expected');
?. _errHas('a = { x = 1, }' & nl, 'expected');
?. _errHas('a = 0xZZ' & nl, 'invalid number');
?. _bad('a = 01' & nl);
?. _bad('a = 1.' & nl);
?. _bad('a = .1' & nl);
?. _bad('a = 1__0' & nl);
?. _bad('a = 0x1_' & nl);
?. _bad('a = 1979-02-31' & nl);
?. _bad('a = 1900-02-29' & nl);
?. _parse('a = 0xdead' & nl)['a'] = 57005;
?. _parse('a = 0o7_7' & nl)['a'] = 63;
?. _parse('a = 0b1_0' & nl)['a'] = 2;
?. _parse('a = 2000-02-29' & nl)['a'].tomlKind() = 'date';

// fs integration: writer and reader do not close the handle
var root = fs.tempDir('fun-toml-test-');
?. root <> nil;
var p = PathJoin([root, 'config.toml']);
var f = fs.open(p, 'w');
?. toml.writer(f).write(_parse('a = 1' & nl & '[s]' & nl & 'b = "x"' & nl));
f.close();
var g = fs.open(p, 'r');
var fd = toml.reader(g).read();
?. fd['a'] = 1;
?. fd['s']['b'] = 'x';
g.close();
?. fs.removeAll(root);
?. fs.exists(root) = false;
