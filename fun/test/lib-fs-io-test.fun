// fs file handles: open/read/write/seek/tell/eof/flush/close. The snapshot
// contains booleans only; the fixture is removed at the end.
use 'fun/lib/fs.fun';

var root = fs.tempDir('fun-fs-io-test-');
var p = PathJoin([root, 'data.bin']);
var bad = false;

var f = fs.open(p, 'w+');
?. f <> nil;
?. f.write('hello') = 5;
?. f.tell() = 5;
?. f.seek(0, 0) = 0;
?. f.read(5) = 'hello';
?. f.tell() = 5;
?. f.read(1) = '';
?. f.eof();
?. f.tell() = 5;
?. f.eof();
?. f.flush();
?. f.close();
?. f.close();

var closed = false;
try
  f.read(1);
except
  closed = true;
end try;
?. closed;

bad = false;
try
  f.write('x');
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.seek(0, 0);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.tell();
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.eof();
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.flush();
except
  bad = true;
end try;
?. bad;

f = fs.open(p);
?. f.read(5) = 'hello';
f.close();

f = fs.open(p, 'r');
?. f.seek(2, 0) = 2;
?. f.seek(1, 1) = 3;
?. f.read(1) = 'l';
?. f.tell() = 4;
f.close();

var big = 0xFFFFFFFF + 1;
f = fs.open(p, 'r+');
?. f.seek(big, 0) = big;
?. f.tell() = big;
f.close();

f = fs.open(p, 'r');
?. f.read(10) = 'hello';
?. f.flush();
f.close();

f = fs.open(p, 'rb');
?. f.read(1) = 'h';
f.close();

f = fs.open(p, 'a');
?. f.write('!') = 1;
?. f.tell() = 6;
f.close();
f = fs.open(p, 'r');
?. f.read(10) = 'hello!';
f.close();

f = fs.open(p, 'w');
?. f.tell() = 0;
?. f.write('xy') = 2;
bad = false;
try
  f.write(123);
except
  bad = true;
end try;
?. bad;
f.close();
?. p.size() = 2;

var pf = PathJoin([root, 'flush.txt']);
f = fs.open(pf, 'w');
?. f.write('flush') = 5;
?. f.flush();
var g = fs.open(pf, 'r');
?. g.read(5) = 'flush';
g.close();
f.close();

f = fs.open(p, 'r+');
?. f.write('Z') = 1;
?. f.seek(0, 0) = 0;
?. f.read(2) = 'Zy';
f.close();

f = fs.open(p, 'w+');
?. f.tell() = 0;
?. f.read(1) = '';
?. f.write('') = 0;
f.close();
?. p.size() = 0;

f = fs.open(p, 'a+');
?. f.write('A') = 1;
?. f.seek(0, 0) = 0;
?. f.read(1) = 'A';
f.close();

var bytes = '';
for i = 0 to 255 do bytes &= i.toChar(); end do;
f = fs.open(p, 'w+');
?. f.write(bytes) = 256;
?. f.seek(0, 0) = 0;
var got = f.read(256);
?. got.length() = 256;
?. got.toByte(0) = 0;
?. got.toByte(255) = 255;
?. f.seek(-1, 2) = 255;
?. f.read(1) = 255.toChar();
f.close();

try
  fs.open(p, 'x');
except
  bad = true;
end try;
?. bad;

bad = false;
try
  fs.open(p, '');
except
  bad = true;
end try;
?. bad;

bad = false;
try
  fs.open(PathJoin([root, 'missing.bin']), 'r');
except
  bad = true;
end try;
?. bad;

f = fs.open(p, 'r');
bad = false;
try
  f.seek(0, 3);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.read(-1);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.read(0x80000000);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.read(0xFFFFFFFF);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.seek(1.5, 0);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.read(1.5);
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.read();
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.seek('', 0);
except
  bad = true;
end try;
?. bad;

?. f.seek(1) = 1;

bad = false;
try
  f.seek();
except
  bad = true;
end try;
?. bad;

bad = false;
try
  f.write('x');
except
  bad = true;
end try;
?. bad;
f.close();

f = fs.open(p, 'w');
bad = false;
try
  f.read(1);
except
  bad = true;
end try;
?. bad;
f.close();

var p2 = PathJoin([root, 'new.txt']);
f = fs.open(p2, 'a');
?. f.write('new') = 3;
f.close();
?. p2.load() = 'new';

var up = PathJoin([root, '中文.bin']);
f = fs.open(up, 'w+');
?. f.write('u') = 1;
f.close();
f = fs.open(up, 'r');
?. f.read(1) = 'u';
f.close();

?. fs.removeAll(root);
?. fs.exists(root) = false;
