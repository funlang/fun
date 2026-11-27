// lib-smtp: open/AUTH/send/message/close semantics against the loopback
// fixture in fun/test/smtp-fixture.py (started by fun/test/run-smtp.sh,
// which also sets SSL_CERT_FILE so the STARTTLS/implicit-TLS verifies are
// deterministic). Transaction bytes come back from the fixture's per-port
// files, so envelope, dot-stuffing and message content are asserted
// byte-for-byte.
use 'fun/lib/smtp.fun';
use 'fun/lib/fs.fun';
use 'fun/lib/io.fun';
use 'fun/lib/lib-base64.fun';

fun ok(cond, name)
  if cond then
    ?. 'PASS ' & name;
  else
    ?. 'FAIL ' & name;
  end if;
end fun;

var cr = 13.toChar();
var nl = 10.toChar();
var OUT = 'fun/test/.smtp-out';

// the fixture names transactions tx-<server port>-<n>.txt
fun readTx(port)
  result = io.readAll(fs.open(OUT & '/tx-' & port & '-1.txt', 'r'));
end fun;

fun capsText(sess)
  var t = '';
  for k: v in sess.capabilities() do t = t & k & ','; end do;
  result = t;
end fun;

//--- plain 25 shape: greeting, EHLO capabilities, PLAIN auth, send --------
var s = smtp.open('127.0.0.1', 18925, [user: 'user@test', pass: 'secret', timeout: 5000]);
ok(capsText(s) =~ %AUTH%, 'plain session exposes the EHLO capabilities');
ok(capsText(s) =~ %8BITMIME%, 'capability values are parsed');

var msg = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'hello',
                        body: 'line1' & nl & 'line2']);
ok(s.send('a@test', ['b@test'], msg), 'plain send returns true');
s.close();

var tx = readTx(18925);
ok(tx =~ %MAIL\x20MAIL\x20FROM:<a@test>%, 'envelope MAIL FROM is recorded');
ok(tx =~ %RCPT\x20TO\x20b@test%, 'envelope RCPT TO is recorded');
ok(tx.subpos('To: b@test') > 0, 'message To header present');
ok(tx.subpos('Subject: hello') > 0, 'ASCII subject passes through');
ok(tx.subpos('Date: ') > 0, 'Date header present');
ok(tx.subpos('Message-ID: <') > 0, 'Message-ID header present');
ok(tx.subpos('Content-Transfer-Encoding: 7bit') > 0, 'ASCII body is 7bit');
ok(tx.subpos('line1' & cr & nl & 'line2') > 0, 'body lines are CRLF');

//--- multiple recipients: envelope carries all, headers only To/Cc --------
s = smtp.open('127.0.0.1', 18925, [timeout: 5000]);
msg = smtp.message([from: 'a@test', 'to': ['b@test', 'c@test'], cc: ['d@test'],
                    subject: 'multi', body: 'x']);
s.send('a@test', ['b@test', 'c@test', 'e@test'], msg);
s.close();
tx = readTx(18925);
ok(tx =~ %RCPT\x20TO\x20b@test,c@test,e@test%, 'all envelope recipients confirmed');
ok(tx.subpos('To: b@test, c@test') > 0, 'To header joins recipients');
ok(tx.subpos('Cc: d@test') > 0, 'Cc header present');

//--- dot-stuffing: leading dots doubled on the wire, restored by the peer --
s = smtp.open('127.0.0.1', 18925, [timeout: 5000]);
msg = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'dots',
                    body: 'line1' & nl & '.leading' & nl & '..double' & nl & 'end']);
s.send('a@test', ['b@test'], msg);
s.close();
tx = readTx(18925);
ok(tx.subpos('line1' & cr & nl & '.leading' & cr & nl & '..double' & cr & nl & 'end') > 0,
   'dot-stuffing is undone by the server');

//--- Bcc: envelope only, never a header ------------------------------------
s = smtp.open('127.0.0.1', 18925, [timeout: 5000]);
msg = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'bcc', body: 'x']);
s.send('a@test', ['b@test', 'hidden@test'], msg);
s.close();
tx = readTx(18925);
ok(tx =~ %RCPT\x20TO\x20b@test,hidden@test%, 'Bcc goes into the envelope');
ok(tx.subpos('Bcc:') < 0, 'Bcc never becomes a header');

//--- connect/greet stage errors ---------------------------------------------
var m = 'no error';
try
  var t1 = smtp.open('127.0.0.1', 18999, [timeout: 2000]);
  t1.close();
except
  m = '' & @;
end try;
ok(m =~ %smtp:\x20connect:%, 'refused connection names the connect stage');

m = 'no error';
try
  var t2 = smtp.open('127.0.0.1', 18967, [timeout: 2000]);
  t2.close();
except
  m = '' & @;
end try;
ok(m = 'smtp: greet: 554 fixture.test rejected', 'non-220 greeting names the greet stage');

//--- reply timeout -----------------------------------------------------------
m = 'no error';
try
  var t3 = smtp.open('127.0.0.1', 18966, [timeout: 1500]);
  t3.close();
except
  m = '' & @;
end try;
ok(m = 'smtp: greet: timeout', 'silent server hits the reply timeout');

//--- 587 shape: auto STARTTLS, re-EHLO, auth over TLS ------------------------
s = smtp.open('127.0.0.1', 18958, [user: 'user@test', pass: 'secret', timeout: 5000]);
ok(not (capsText(s) =~ %STARTTLS%), 'capabilities reset after the upgrade');
msg = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'secure', body: 'tls body']);
ok(s.send('a@test', ['b@test'], msg), 'STARTTLS session delivers mail');
s.close();
tx = readTx(18958);
ok(tx.subpos('tls body') > 0, 'STARTTLS payload arrives intact');

//--- 'none' keeps the session plain ------------------------------------------
s = smtp.open('127.0.0.1', 18958, [user: 'user@test', pass: 'secret', timeout: 5000, tls: 'none']);
ok(s.send('a@test', ['b@test'],
          smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'plain', body: 'x'])),
   'tls none still delivers on an advertising server');
s.close();

//--- 465 shape: implicit TLS --------------------------------------------------
s = smtp.open('127.0.0.1', 18965, [user: 'user@test', pass: 'secret', timeout: 5000, tls: 'implicit']);
ok(s.send('a@test', ['b@test'],
          smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'implicit', body: 'x'])),
   'implicit TLS session delivers mail');
s.close();
tx = readTx(18965);
ok(tx.subpos('Subject: implicit') > 0, 'implicit TLS payload arrives intact');

//--- port 465 implies implicit TLS: covered by the 'implicit' case above
// (binding the privileged port 465 is not possible for an unprivileged test)

//--- AUTH ---------------------------------------------------------------
m = 'no error';
try
  var t4 = smtp.open('127.0.0.1', 18925, [user: 'user@test', pass: 'wrong', timeout: 5000]);
  t4.close();
except
  m = '' & @;
end try;
ok(m =~ %smtp:\x20auth:\x20535%, 'failed auth names the stage and the reply');

//--- RCPT rejection -----------------------------------------------------------
m = 'no error';
try
  var t5 = smtp.open('127.0.0.1', 18955, [timeout: 5000]);
  t5.send('a@test', ['bad@test'],
          smtp.message([from: 'a@test', 'to': ['bad@test'], subject: 'x', body: 'x']));
  t5.close();
except
  m = '' & @;
end try;
ok(m = 'smtp: rcpt: bad@test: 550 no such user', 'rejected recipient names the address');

//--- close: QUIT, idempotent, send after close raises -------------------------
s = smtp.open('127.0.0.1', 18925, [timeout: 5000]);
ok(s.close(), 'close returns true');
ok(s.close(), 'close is idempotent');
m = 'no error';
try
  s.send('a@test', ['b@test'], smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'x', body: 'x']));
except
  m = '' & @;
end try;
ok(m = 'smtp: send: session is closed', 'send after close raises');

//--- message builder: pure functions, no server -------------------------------
var pm = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'hi', body: 'hello']);
ok(pm.subpos('From: a@test') = 0, 'builder starts with From');
ok(pm.subpos(cr & nl & cr & nl) > 0, 'headers end with a blank line');
ok(pm.subpos('Subject: hi') > 0, 'ASCII subject stays literal');
ok(pm.subpos('hello') > 0, 'ASCII body stays literal');
ok(pm.subpos('MIME-Version: 1.0') > 0, 'MIME-Version present');

var cn = smtp.message([from: 'a@test', 'to': ['b@test'], subject: '中文报告', body: '中文正文']);
ok(cn.subpos('Subject: =?utf-8?B?') > 0, 'Chinese subject becomes an encoded word');
ok(cn.subpos('Content-Transfer-Encoding: base64') > 0, 'Chinese body is base64');
var b64line = cn.substr(cn.subpos(cr & nl & cr & nl) + 4);
ok(fromBase64(b64line) = '中文正文' & cr & nl, 'base64 body decodes back to the original');

var lf = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'lf', body: 'a' & nl & 'b' & nl]);
ok(lf.subpos('a' & cr & nl & 'b') > 0 and lf.subpos('a' & nl & 'b') < 0, 'bare LF is normalized to CRLF');

var am = smtp.message([from: 'a@test', 'to': ['b@test'], subject: 'att', body: 'see attachment',
                       attachments: [[name: 'a.txt', data: 'file-content'],
                                     [name: 'b.bin', data: 'x' & nl & 'y']]]);
ok(am.subpos('Content-Type: multipart/mixed; boundary="fun-') > 0, 'attachments make multipart/mixed');
ok(am.subpos('Content-Disposition: attachment; filename="a.txt"') > 0, 'attachment filename is declared');
var boundary = am.match(/boundary="([^"]+)"/).@(1);
var part1 = am.substr(am.subpos('filename="a.txt"'));
ok(part1.subpos(Str2Base64('file-content')) > 0, 'attachment content is base64');
// decode each attachment part back to the original bytes
fun decodePart_after(marker)
  var at = am.subpos(marker);
  var rest = am.substr(at);
  var start = rest.subpos(cr & nl & cr & nl) + 4;
  var endi = rest.subpos(cr & nl & '--');
  result = fromBase64(rest.substr(start, endi - start));
end fun;
ok(decodePart_after('filename="a.txt"') = 'file-content', 'attachment decodes byte-for-byte');
ok(decodePart_after('filename="b.bin"') = 'x' & nl & 'y', 'second attachment decodes byte-for-byte');ok(am.subpos('--' & boundary & '--') > 0, 'closing boundary present');

?. 'done';
