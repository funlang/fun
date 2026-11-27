#!/usr/bin/env python3
"""Loopback SMTP fixture for fun/test/lib-smtp-test.fun.

Six 127.0.0.1 ports, each one behaviour the test asserts on. All TLS uses the
committed test PKI in fun/test/tls (srv cert, 100-year certs):

  18925  plain 25 shape: 220, EHLO (no STARTTLS), AUTH PLAIN/LOGIN, MAIL/RCPT/DATA
  18958  587 shape: EHLO advertises STARTTLS; after STARTTLS the socket is the
         srv-cert TLS server and the session continues (re-EHLO, AUTH, mail)
  18965  465 shape: implicit TLS first, then SMTP
  (port 465 itself is privileged, so the port-implies-TLS rule is covered by
   the opts.tls: 'implicit' case on 18965)
  18955  plain, no AUTH: RCPT TO <bad@test> is rejected with 550, others accepted
  18966  accepts and never responds (timeout test)
  18967  answers 554 instead of the 220 greeting (greet-stage error test)

Correct credentials everywhere: user@test / secret.

Every accepted DATA transaction writes one file under argv[2] (the output
dir), named tx-<server port>-<n>.txt:

  MAIL FROM <addr>
  RCPT TO <addr>,<addr>
  ---
  <message bytes exactly as received, dot-stuffing removed>

argv[1] is the ready marker (written once every listener is bound).
"""

import base64
import os
import socket
import ssl
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
TLS_DIR = os.path.join(HERE, 'tls')

USER = 'user@test'
PASS = 'secret'

P_PLAIN = 18925
P_STARTTLS = 18958
P_IMPLICIT = 18965
P_REJECT = 18955
P_SILENT = 18966
P_BADGREET = 18967


def srv_ctx():
    c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    c.load_cert_chain(os.path.join(TLS_DIR, 'srv.pem'),
                      os.path.join(TLS_DIR, 'srv.key'))
    return c


class Conn:
    """Buffered CRLF reader/writer over a plain or TLS socket."""

    def __init__(self, sock):
        self.sock = sock
        self.buf = b''

    def readline(self):
        while b'\r\n' not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError('peer closed')
            self.buf += chunk
        line, self.buf = self.buf.split(b'\r\n', 1)
        return line

    def sendline(self, data):
        raw = data if isinstance(data, bytes) else data.encode()
        self.sock.sendall(raw + b'\r\n')


class Session:
    """One client connection: command loop + transaction recording."""

    def __init__(self, conn, out_dir, advertise_starttls,
                 reject_bad_rcpt, silent, bad_greeting):
        self.c = conn
        self.out_dir = out_dir
        self.advertise_starttls = advertise_starttls
        self.reject_bad_rcpt = reject_bad_rcpt
        self.silent = silent
        self.bad_greeting = bad_greeting
        self.authed = False
        self.tx = None          # current transaction being recorded
        self.n = 0

    def reply(self, code, lines):
        if isinstance(lines, str):
            lines = [lines]
        first = len(lines) - 1
        for i, text in enumerate(lines):
            sep = ' ' if i == first else '-'
            self.c.sendline(('%d%s%s' % (code, sep, text)).encode())

    def ehlo_lines(self):
        lines = ['fixture.test']
        if self.advertise_starttls and not self.authed:
            lines.append('STARTTLS')
        lines.append('SIZE 35882577')
        lines.append('8BITMIME')
        # AUTH last: the final reply line carries '250 <text>' and exercises
        # the separator strip (a leading space would corrupt the mech lookup)
        lines.append('AUTH PLAIN LOGIN')
        return lines

    def handle(self):
        try:
            if self.silent:
                # accept and never answer: the client must hit its timeout
                threading.Event().wait()
            if self.bad_greeting:
                self.reply(554, 'fixture.test rejected')
                return
            self.reply(220, 'fixture.test ESMTP ready')
            while True:
                line = self.c.readline().decode('utf-8', 'replace')
                verb = line.split(' ', 1)[0].upper()
                if verb == 'EHLO' or verb == 'HELO':
                    self.reply(250, self.ehlo_lines())
                elif verb == 'STARTTLS' and self.advertise_starttls:
                    self.reply(220, 'Ready to start TLS')
                    tls = srv_ctx().wrap_socket(self.c.sock, server_side=True)
                    self.c = Conn(tls)
                    # the next EHLO re-advertises without STARTTLS
                    self.advertise_starttls = False
                elif verb == 'AUTH':
                    if not self.auth(line):
                        return
                elif verb == 'MAIL':
                    if self.tx is None:
                        self.tx = {'from': line, 'rcpt': []}
                    self.reply(250, 'OK')
                elif verb == 'RCPT':
                    addr = line.split(':', 1)[1].strip('<>') if ':' in line else line
                    if self.reject_bad_rcpt and 'bad@test' in addr:
                        self.reply(550, 'no such user')
                        return
                    if self.tx is not None:
                        self.tx['rcpt'].append(addr)
                    self.reply(250, 'OK')
                elif verb == 'DATA':
                    self.reply(354, 'End your data with <CRLF>.<CRLF>')
                    self.record_data()
                    self.reply(250, 'OK: queued as %d' % self.n)
                elif verb == 'RSET':
                    self.tx = None
                    self.reply(250, 'OK')
                elif verb == 'NOOP':
                    self.reply(250, 'OK')
                elif verb == 'QUIT':
                    self.reply(221, 'Bye')
                    return
                else:
                    self.reply(500, 'command not recognized')
        except Exception:
            pass

    def auth(self, line):
        parts = line.split(' ')
        mech = parts[1].upper() if len(parts) > 1 else ''
        if mech == 'PLAIN':
            if len(parts) < 3:
                self.reply(535, 'authentication failed')
                return False
            try:
                raw = base64.b64decode(parts[2]).split(b'\x00')
                ok = len(raw) == 3 and raw[1].decode() == USER and raw[2].decode() == PASS
            except Exception:
                ok = False
            if not ok:
                self.reply(535, 'authentication failed')
                return False
        elif mech == 'LOGIN':
            self.reply(334, base64.b64encode(b'Username:').decode())
            user = base64.b64decode(self.c.readline()).decode()
            self.reply(334, base64.b64encode(b'Password:').decode())
            pw = base64.b64decode(self.c.readline()).decode()
            ok = user == USER and pw == PASS
            if not ok:
                self.reply(535, 'authentication failed')
                return False
        else:
            self.reply(504, 'unrecognized authentication type')
            return False
        self.authed = True
        self.reply(235, 'authentication successful')
        return True

    def record_data(self):
        lines = []
        while True:
            line = self.c.readline()
            if line == b'.':
                break
            if line.startswith(b'.'):
                line = line[1:]
            lines.append(line)
        self.n += 1
        msg = b'\r\n'.join(lines)
        path = os.path.join(self.out_dir,
                            'tx-%d-%d.txt' % (self.c.sock.getsockname()[1], self.n))
        with open(path, 'wb') as f:
            if self.tx:
                f.write(('MAIL %s\n' % self.tx['from']).encode())
                f.write(('RCPT TO %s\n' % ','.join(self.tx['rcpt'])).encode())
            else:
                f.write(b'MAIL (none)\nRCPT TO (none)\n')
            f.write(b'---\n')
            f.write(msg)


def serve(port, out_dir, advertise_starttls, implicit_tls, reject_bad_rcpt,
          silent=False, bad_greeting=False):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(16)
    ctx = srv_ctx() if implicit_tls else None
    while True:
        try:
            c, _ = s.accept()
        except OSError:
            return

        def handle(c=c):
            try:
                if implicit_tls:
                    c = ctx.wrap_socket(c, server_side=True)
                conn = Conn(c)
                sess = Session(conn, out_dir, advertise_starttls,
                               reject_bad_rcpt, silent, bad_greeting)
                sess.handle()
            except Exception:
                try:
                    c.close()
                except Exception:
                    pass

        threading.Thread(target=handle, daemon=True).start()


def main():
    marker = sys.argv[1] if len(sys.argv) > 1 else None
    out_dir = sys.argv[2] if len(sys.argv) > 2 else '.'
    os.makedirs(out_dir, exist_ok=True)
    plans = [
        (P_PLAIN, False, False, False, False, False),
        (P_STARTTLS, True, False, False, False, False),
        (P_IMPLICIT, False, True, False, False, False),
        (P_REJECT, False, False, True, False, False),
        (P_SILENT, False, False, False, True, False),
        (P_BADGREET, False, False, False, False, True),
    ]
    threads = []
    for (port, advertise_starttls, implicit_tls, reject_bad_rcpt, silent,
         bad_greeting) in plans:
        t = threading.Thread(
            target=serve,
            args=(port, out_dir, advertise_starttls, implicit_tls,
                  reject_bad_rcpt, silent, bad_greeting),
            daemon=True)
        t.start()
        threads.append(t)
    if marker:
        with open(marker, 'w') as f:
            f.write('ready\n')
    threading.Event().wait()


if __name__ == '__main__':
    main()
