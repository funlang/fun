// io: generic reader/writer helpers. The snapshot contains booleans only.
use 'fun/lib/io.fun';
use 'fun/lib/csv.fun';
use 'fun/lib/fs.fun';
use 'fun/lib/lib-path.fun';

var nl = 10.toChar();

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

class _CountWriter()
  var text = '';
  var chunks = 0;
  fun write(s)
    text &= s;
    chunks += 1;
    result = s.length();
  end fun;
end class;

class _FailWriter()
  fun write(s)
    raise 'io: test write failure';
  end fun;
end class;

// process stdio API and validation (no terminal read/write here)
var stdinR = io.stdin();
?. stdinR.read(0) = '';
var stdBad = false;
try
  stdinR.read(-1);
except
  stdBad = true;
end try;
?. stdBad;
stdBad = false;
try
  stdinR.read('x');
except
  stdBad = true;
end try;
?. stdBad;
stdBad = false;
try
  stdinR.read(nil);
except
  stdBad = true;
end try;
?. stdBad;
stdBad = false;
try
  stdinR.read(1.5);
except
  stdBad = true;
end try;
?. stdBad;
stdBad = false;
try
  stdinR.read(0x80000000);
except
  stdBad = true;
end try;
?. stdBad;
var stdoutW = io.stdout();
?. stdoutW.write('') = 0;
?. stdoutW.write(nil) = 0;
?. io.stderr().write('') = 0;
?. io.stderr().write(nil) = 0;
stdBad = false;
try
  stdoutW.write(0);
except
  stdBad = true;
end try;
?. stdBad;
stdBad = false;
try
  stdoutW.write(false);
except
  stdBad = true;
end try;
?. stdBad;

// buffer construction and reading
var b = io.buffer();
?. b.text() = '';
?. b.length() = 0;
?. b.read(1) = '';
?. b.read(0) = '';

b = io.buffer(nil);
?. b.text() = '';

b = io.buffer('hello');
?. b.length() = 5;
?. b.read(2) = 'he';
?. b.length() = 3;
?. b.text() = 'llo';
?. b.read(10) = 'llo';
?. b.length() = 0;
?. b.text() = '';
?. b.read(1) = '';

// writes append; reads and writes keep independent positions
b = io.buffer();
?. b.write('ab') = 2;
?. b.write('') = 0;
?. b.write(nil) = 0;
?. b.text() = 'ab';
?. b.read(1) = 'a';
?. b.write('c') = 1;
?. b.text() = 'bc';
?. b.length() = 2;
?. b.read(10) = 'bc';
?. b.length() = 0;
?. b.write('0') = 1;
?. b.read(1) = '0';

// zero strings stay observable
b = io.buffer('0');
?. b.length() = 1;
?. b.read(1) = '0';
?. b.read(1) = '';
?. b.reset();
?. b.text() = '';
?. b.length() = 0;
?. b.read(1) = '';

// constructor and argument errors
var bad = false;
try
  io.buffer(0);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  io.buffer(new []);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  io.buffer('x').read(nil);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  io.buffer('x').read('1');
except
  bad = true;
end try;
?. bad;

bad = false;
try
  io.buffer('x').read(-1);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  io.buffer().write(0);
except
  bad = true;
end try;
?. bad;

// readAll: empty, short reads, chunk boundaries, zero strings
?. io.readAll(io.buffer()) = '';
?. io.readAll(io.buffer('abc')) = 'abc';
?. io.readAll(io.buffer('0')) = '0';
?. io.readAll(_ShortReader('abcdef', 1)) = 'abcdef';
?. io.readAll(_ShortReader('00', 1)) = '00';
?. io.readAll(_ShortReader('abc', 2)) = 'abc';
var big = 'x'.x(9000);
?. io.readAll(io.buffer(big)) = big;
?. io.readAll(_ShortReader(big, 1000)).length() = 9000;

// copy: return count, short reads, zero strings, empty source
var dst = io.buffer();
var src = io.buffer('hello');
?. io.copy(dst, src) = 5;
?. dst.text() = 'hello';
?. src.text() = '';

dst = io.buffer();
src = io.buffer();
?. io.copy(dst, src) = 0;
?. dst.text() = '';

var cw = _CountWriter();
?. io.copy(cw, _ShortReader('abc', 1)) = 3;
?. cw.text = 'abc';
?. cw.chunks = 3;

cw = _CountWriter();
?. io.copy(cw, io.buffer('0')) = 1;
?. cw.text = '0';

bad = false;
try
  io.copy(_FailWriter(), io.buffer('x'));
except
  bad = ('' & @).subpos('test write failure') >= 0;
end try;
?. bad;

// writeString: string, empty, nil and zero string
dst = io.buffer();
?. io.writeString(dst, 'hello') = 5;
?. dst.text() = 'hello';
?. io.writeString(dst, '') = 0;
?. io.writeString(dst, nil) = 0;
?. dst.text() = 'hello';
?. io.writeString(dst, '0') = 1;
?. dst.text() = 'hello0';

bad = false;
try
  io.writeString(dst, 0);
except
  bad = true;
end try;
?. bad;

// fs handles satisfy the same protocol
var root = fs.tempDir('fun-io-test-');
?. root <> nil;
var p = PathJoin([root, 'data.txt']);
var f = fs.open(p, 'w');
?. io.writeString(f, 'hello') = 5;
?. io.copy(f, io.buffer(' world')) = 6;
f.close();

var g = fs.open(p, 'r');
?. io.readAll(g) = 'hello world';
g.close();

g = fs.open(p, 'r');
dst = io.buffer();
?. io.copy(dst, g) = 11;
g.close();
?. dst.text() = 'hello world';
?. fs.removeAll(root);
?. fs.exists(root) = false;

// existing CSV readers/writers accept io.buffer directly
var cb = io.buffer('a,b' & nl & '1,2' & nl);
var cr = csv.reader(cb);
var row = cr.read();
?. row <> nil;
?. row[0] = 'a';
?. row[1] = 'b';
row = cr.read();
?. row[0] = '1';
?. row[1] = '2';
?. cr.read() = nil;

var out = io.buffer();
var cw2 = csv.writer(out);
cw2.write(['x', 'y']);
?. out.text() = 'x,y' & nl;
var rr = csv.reader(out).read();
?. rr[0] = 'x';
?. rr[1] = 'y';
