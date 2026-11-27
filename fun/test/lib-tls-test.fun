// lib-tls: connect/wrap/verify/close semantics against the loopback fixture
// in fun/test/tls-fixture.py (started by fun/test/run-tls.sh, which also sets
// SSL_CERT_FILE to the fixture CA so the verify-on paths are deterministic).
use 'fun/lib/tls.fun';
use 'fun/lib/lib-winsock-unx.fun';
use 'fun/lib/io.fun';

fun ok(cond, name)
  if cond then
    ?. 'PASS ' & name;
  else
    ?. 'FAIL ' & name;
  end if;
end fun;

var cr = 13.toChar();
var nl = 10.toChar();

// a moment for the fixture to have sent its greeting before a wrap
var _usleep = LibC().getapi('usleep', 'i:i');
fun pause(us)
  _usleep(us);
end fun;

//--- implicit TLS: connect, write, read, close ---
var s = tls.connect('localhost', 18741, [verify: false, timeout: 5000]);
s.write('GET /' & cr & nl);
var r = s.read(4096);
ok(r.substr(0, 15) = 'HTTP/1.0 200 OK', 'implicit connect roundtrip');
ok(s.write('x') = 1, 'write returns the byte count');
ok(s.close(), 'close returns true');
ok(s.close(), 'close is idempotent');

//--- read size validation matches the io contract ---
var s2 = tls.connect('localhost', 18741, [verify: false, timeout: 5000]);
var m = '';
try
  s2.read(nil);
except
  m = '' & @;
end try;
ok(m = 'tls: read size required', 'read size required');
m = '';
try
  s2.read(-1);
except
  m = '' & @;
end try;
ok(m = 'tls: read size must be >= 0', 'read size negative rejected');
ok(s2.read(0) = '', 'read zero returns empty');
s2.close();

//--- verification on: CA (SSL_CERT_FILE) + hostname + SNI + IP SAN ---
var v = tls.connect('localhost', 18741, [timeout: 5000]);
v.write('GET /' & cr & nl);
ok(v.read(4096).substr(0, 15) = 'HTTP/1.0 200 OK', 'verify on: CA + hostname + SNI');
v.close();

var v2 = tls.connect('127.0.0.1', 18741, [timeout: 5000]);
v2.write('GET /' & cr & nl);
ok(v2.read(4096).substr(0, 15) = 'HTTP/1.0 200 OK', 'verify on: IP subjectAltName');
v2.close();

//--- verification failures name the cause ---
var mm = 'no error';
try
  var t1 = tls.connect('localhost', 18742, [timeout: 5000]);
  t1.close();
except
  mm = '' & @;
end try;
ok(mm = 'tls: certificate: hostname mismatch', 'hostname mismatch rejected');

var ss = 'no error';
try
  var t2 = tls.connect('localhost', 18747, [timeout: 5000]);
  t2.close();
except
  ss = '' & @;
end try;
ok(ss = 'tls: certificate: self-signed certificate', 'self-signed chain rejected');

//--- wrap: the STARTTLS shape ---
var fd = ConnectSocket('127.0.0.1', 18743);
SendAll(fd, 'HELLO' & cr & nl);
var w = tls.wrap(fd, [host: 'localhost', verify: false, timeout: 5000]);
w.write('PING' & cr & nl);
ok(w.read(4096) = 'tls-ok', 'wrap upgrades the connection in place');
w.close();

// wrap refuses to swallow plain bytes read before the upgrade
var fd2 = ConnectSocket('127.0.0.1', 18744);
pause(300000);
var mu = '';
try
  tls.wrap(fd2, [host: 'localhost', verify: false, timeout: 5000]);
except
  mu = '' & @;
end try;
ok(mu = 'tls: wrap: connection has unread data', 'wrap rejects unread data');
LibC().getapi('close', 'i:i')(fd2);

// wrap requires the hostname
var fd3 = ConnectSocket('127.0.0.1', 18743);
var mh = '';
try
  tls.wrap(fd3, [verify: false, timeout: 5000]);
except
  mh = '' & @;
end try;
ok(mh = 'tls: opts.host is required', 'wrap requires opts.host');
LibC().getapi('close', 'i:i')(fd3);

//--- failure stages ---
var mc = '';
try
  var t3 = tls.connect('127.0.0.1', 18799, [timeout: 2000]);
  t3.close();
except
  mc = '' & @;
end try;
ok(mc =~ %tls:\x20connect:%, 'refused connection names the connect stage');

var md = '';
try
  var t4 = tls.connect('no-such-host-tls-test.invalid', 443, [timeout: 2000]);
  t4.close();
except
  md = '' & @;
end try;
ok(md =~ %tls:\x20resolve:%, 'unresolved host names the resolve stage');

var mh2 = '';
try
  var t5 = tls.connect('127.0.0.1', 18744, [timeout: 3000]);
  t5.close();
except
  mh2 = '' & @;
end try;
ok(mh2 =~ %tls:\x20handshake:%, 'plain-text server names the handshake stage');

var mt = '';
try
  var t6 = tls.connect('127.0.0.1', 18745, [timeout: 1000]);
  t6.close();
except
  mt = '' & @;
end try;
ok(mt = 'tls: handshake: timeout', 'handshake honours the timeout');

//--- EOF: the server answers and closes ---
var e = tls.connect('localhost', 18746, [verify: false, timeout: 5000]);
ok(e.read(4096) = 'bye', 'read returns the payload');
ok(e.read(4096) = '', 'read returns empty at EOF');
e.close();

//--- io contract: copy and scanner over a tls stream ---
var c1 = tls.connect('localhost', 18746, [verify: false, timeout: 5000]);
var buf = io.buffer('');
io.copy(buf, c1);
ok(buf.text() = 'bye', 'io.copy drains a tls stream');
c1.close();

var c2 = tls.connect('localhost', 18746, [verify: false, timeout: 5000]);
var sc = io.scanner(c2);
ok(sc.scan() and sc.text() = 'bye', 'io.scanner reads a tls line');
ok(not sc.scan(), 'io.scanner at eof');
c2.close();

//--- reads and writes after close raise ---
var a = tls.connect('localhost', 18741, [verify: false, timeout: 5000]);
a.close();
var ma = '';
try
  a.read(16);
except
  ma = '' & @;
end try;
ok(ma = 'tls: read: stream is closed', 'read after close raises');
var mb = '';
try
  a.write('x');
except
  mb = '' & @;
end try;
ok(mb = 'tls: write: stream is closed', 'write after close raises');

?. 'done';
