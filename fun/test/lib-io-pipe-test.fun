// io: OS pipe pair; small in-process payloads only (no concurrency).
use 'fun/lib/io.fun';

var p = io.pipe();
?. p.writer.write('') = 0;
?. p.writer.write(nil) = 0;
?. p.reader.read(0) = '';

var bad = false;
try
  p.reader.read(-1);
except
  bad = true;
end try;
?. bad;

?. p.writer.write('ab') = 2;
?. p.reader.read(6) = 'ab';

var data = 'a' & 0.toChar() & 1.toChar() & 10.toChar() & 255.toChar() & 'B';
?. p.writer.write(data) = data.length();
var got = '';
while got.length() < data.length() do
  var s = p.reader.read(data.length() - got.length());
  if s = '' then exit; end if;
  got &= s;
end do;
?. got = data;

?. p.writer.close();
?. p.writer.close();
?. p.reader.read(1) = '';
?. p.reader.read(1) = '';
?. p.close();
?. p.close();

bad = false;
try
  p.reader.read(1);
except
  bad = '' & @;
end try;
?. bad.subpos('closed') >= 0;

bad = false;
try
  p.writer.write('x');
except
  bad = '' & @;
end try;
?. bad.subpos('closed') >= 0;

var p2 = io.pipe();
p2.writer.write('xyz');
p2.writer.close();
?. io.readAll(p2.reader) = 'xyz';
?. p2.reader.read(1) = '';
?. p2.close();

var p3 = io.pipe();
p3.writer.write('hello');
p3.writer.close();
var dst = io.buffer();
?. io.copy(dst, p3.reader) = 5;
?. dst.text() = 'hello';
?. p3.reader.read(1) = '';
?. p3.close();

var p4 = io.pipe();
p4.reader.close();
bad = false;
try
  p4.reader.read(1);
except
  bad = '' & @;
end try;
?. bad.subpos('closed') >= 0;
?. p4.close();
?. p4.close();
bad = false;
try
  p4.writer.write('x');
except
  bad = '' & @;
end try;
?. bad.subpos('closed') >= 0;

var p5 = io.pipe();
p5.writer.close();
bad = false;
try
  p5.writer.write('x');
except
  bad = '' & @;
end try;
?. bad.subpos('closed') >= 0;
?. p5.close();

var p7 = io.pipe();
p7.writer.write('z');
?. p7.close();
bad = false;
try
  p7.reader.read(1);
except
  bad = ('' & @).subpos('closed') >= 0;
end try;
?. bad;

if 'host'.arg().getJson(fd: true).os = 'windows' then
  // Windows can report a broken pipe as an error; Unix would raise SIGPIPE.
  var p6 = io.pipe();
  p6.reader.close();
  bad = false;
  try
    p6.writer.write('x');
  except
    bad = ('' & @).subpos('write failed') >= 0;
  end try;
  ?. bad;
  p6.close();
else
  ?. true;
end if;
