#!/usr/bin/env python3
"""Loopback TLS fixture for fun/test/lib-tls-test.fun.

Listens on seven 127.0.0.1 ports, each exercising one behaviour the test
asserts on. All TLS servers use the committed test PKI in fun/test/tls
(100-year certs, test-only CA):

  18741  srv cert    implicit TLS, answers one HTTP-ish response per request
  18742  other cert  same, but the name is other.example.com (mismatch target)
  18743  srv cert    STARTTLS shape: reads one plain line, then handshakes
  18744  none        sends bytes immediately, never handshakes (unread peek)
  18745  none        accepts and sleeps (connect/handshake timeout)
  18746  srv cert    sends 'bye' and closes (EOF / io.copy / scanner)
  18747  ss cert     self-signed chain (verify rejection target)

Every listener is bound before the ready marker (argv[1]) is written, so a
port that is still held by a stale fixture fails startup instead of leaving
run-tls.sh to connect to the wrong server.
"""

import os
import socket
import ssl
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TLS_DIR = os.path.join(HERE, 'tls')

P_HTTP = 18741
P_OTHER = 18742
P_STARTTLS = 18743
P_EARLY = 18744
P_BLACKHOLE = 18745
P_EOF = 18746
P_SELF = 18747


def server_ctx(name):
    c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    c.load_cert_chain(os.path.join(TLS_DIR, name + '.pem'),
                      os.path.join(TLS_DIR, name + '.key'))
    return c


def listener(port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(16)
    return s


def _close(c):
    try:
        c.close()
    except Exception:
        pass


def http_handler(ctx):
    def handle(c):
        try:
            t = ctx.wrap_socket(c, server_side=True)
            t.recv(4096)
            t.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok')
            t.close()
        except Exception:
            _close(c)
    return handle


def _read_line(c):
    """Read up to and including the newline, one byte at a time.

    A buffered recv here would read ahead into the TLS ClientHello: the client
    starts the handshake as soon as the plain line is sent, so the two can
    arrive together. Reading exactly one line leaves the rest queued for
    ctx.wrap_socket(); the old single recv(1024) made the STARTTLS case race
    (observed as a macOS CI failure).
    """
    buf = b''
    while not buf.endswith(b'\n'):
        b = c.recv(1)
        if not b:
            break
        buf += b
    return buf


def starttls_handler(ctx):
    def handle(c):
        try:
            _read_line(c)
            t = ctx.wrap_socket(c, server_side=True)
            t.recv(4096)
            t.sendall(b'tls-ok')
            t.close()
        except Exception:
            _close(c)
    return handle


def early_handler(c):
    try:
        c.sendall(b'early-data')
        time.sleep(5)
        c.close()
    except Exception:
        _close(c)


def blackhole_handler(c):
    threading.Thread(target=_sleep_on, args=(c,), daemon=True).start()


def _sleep_on(c):
    time.sleep(300)
    _close(c)


def eof_handler(ctx):
    def handle(c):
        try:
            t = ctx.wrap_socket(c, server_side=True)
            t.sendall(b'bye')
            t.close()
        except Exception:
            _close(c)
    return handle


def serve(s, handle):
    while True:
        try:
            c, _ = s.accept()
        except OSError:
            return
        handle(c)


def main():
    marker = sys.argv[1] if len(sys.argv) > 1 else None
    srv_ctx = server_ctx('srv')
    plans = [
        (P_HTTP, http_handler(srv_ctx)),
        (P_OTHER, http_handler(server_ctx('other'))),
        (P_STARTTLS, starttls_handler(srv_ctx)),
        (P_EARLY, early_handler),
        (P_BLACKHOLE, blackhole_handler),
        (P_EOF, eof_handler(srv_ctx)),
        (P_SELF, http_handler(server_ctx('ss'))),
    ]
    listeners = [(listener(port), handle) for port, handle in plans]
    for s, handle in listeners:
        threading.Thread(target=serve, args=(s, handle), daemon=True).start()
    if marker:
        with open(marker, 'w') as f:
            f.write('ready\n')
    threading.Event().wait()


if __name__ == '__main__':
    main()
