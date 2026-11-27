// smtp-demo: build a message and either send it through an SMTP server or,
// with no arguments, print the message offline. The host, account and
// recipient come from the environment; the protocol and the MIME builder are
// pure Fun on top of the tls module.
use '../../../lib/smtp.fun';
use '../../../lib/env.fun';

var host = env.get('SMTP_HOST', '');
var user = env.get('SMTP_USER', '');
var pass = env.get('SMTP_PASS', '');
var rcpt = env.get('SMTP_TO', '');
var port = env.get('SMTP_PORT', '587').toNum(0);
// offline printing still needs a well-formed envelope
var from = user <> '' and user or 'demo@example.com';
var to1 = rcpt <> '' and rcpt or 'you@example.com';

var msg = smtp.message([from: from, 'to': [to1],
                        subject: 'smtp-demo 邮件',
                        body: '正文第一行' & 10.toChar() & '正文第二行',
                        attachments: [[name: 'hello.txt', data: '附件内容']]]);

if host = '' or rcpt = '' then
  // offline: show what would go on the wire (the dot-stuffed DATA form)
  ?. msg;
  ?. '---';
  ?. 'set SMTP_HOST/SMTP_USER/SMTP_PASS/SMTP_TO (and optional SMTP_PORT) to send';
else
  var s = smtp.open(host, port, [user: user, pass: pass, timeout: 10000]);
  s.send(user, [rcpt], msg);
  s.close();
  ?. 'sent to ' & rcpt;
end if;
