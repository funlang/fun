// tls-demo: fetch a page over TLS. Verification (certificate chain, hostname)
// is on by default and the CA store is the system's; TLS itself comes from the
// host system library, so this needs libssl (Linux/macOS) or SChannel.
use '../../../lib/tls.fun';

var cr = 13.toChar();
var nl = 10.toChar();

var s = tls.connect('example.com', 443, [timeout: 10000]);
?. 'connected: ' & s.write('GET / HTTP/1.0' & cr & nl & 'Host: example.com' & cr & nl & cr & nl) & ' bytes sent';

var body = s.read(16384);
?. 'status: ' & body.substr(0, 17);

s.close();
?. 'done';
