// io: process stdio integration; driven by lib-io-stdio-test.sh.
use 'fun/lib/io.fun';

var nl = 10.toChar();
var r = io.stdin();
var o = io.stdout();
var e = io.stderr();

var first = '';
while first.length() < 3 do
  var s = r.read(3 - first.length());
  if s = '' then exit; end if;
  first &= s;
end do;

o.write('out:' & first & nl);
e.write('err:' & first & nl);
o.write('rest:' & io.readAll(r) & nl);
