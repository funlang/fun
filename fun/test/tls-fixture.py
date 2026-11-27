#!/usr/bin/env python3
"""Loopback TLS fixture for fun/test/lib-tls-test.fun.

Listens on six 127.0.0.1 ports, each exercising one behaviour the test
asserts on. All TLS servers use the committed test PKI in fun/test/tls
(100-year certs, test-only CA):

  18741  srv cert    implicit TLS, answers one HTTP-ish response per request
  18742  other cert  same, but the name is other.example.com (mismatch target)
  18743  srv cert    STARTTLS shape: reads one plain line, then handshakes
  18744  none        sends bytes immediately, never handshakes (unread peek)
  18745  none        accepts and sleeps (connect/handshake timeout)
  18746  srv cert    sends 'bye' and closes (EOF / io.copy / scanner)
  18747  ss cert     self-signed chain (verify rejection target)

Writes the ready marker given as argv[1] once every listener is bound.
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


def http_server(port, cert):
    ctx = server_ctx(cert)

    def run():
        s = listener(port)
        while True:
            try:
                c, _ = s.accept()
            except OSError:
                return
            try:
                t = ctx.wrap_socket(c, server_side=True)
                t.recv(4096)
                t.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\nok')
                t.close()
            except Exception:
                try:
                    c.close()
                except Exception:
                    pass

    return run


def starttls_server(port):
    ctx = server_ctx('srv')

    def run():
        s = listener(port)
        while True:
            try:
                c, _ = s.accept()
            except OSError:
                return
            try:
                c.recv(1024)
                t = ctx.wrap_socket(c, server_side=True)
                t.recv(4096)
                t.sendall(b'tls-ok')
                t.close()
            except Exception:
                try:
                    c.close()
                except Exception:
                    pass

    return run


def early_server(port):
    def run():
        s = listener(port)
        while True:
            try:
                c, _ = s.accept()
            except OSError:
                return
            try:
                c.sendall(b'early-data')
                time.sleep(5)
                c.close()
            except Exception:
                pass

    return run


def blackhole_server(port):
    def run():
        s = listener(port)
        while True:
            try:
                c, _ = s.accept()
            except OSError:
                return
            threading.Thread(target=_sleep_on, args=(c,), daemon=True).start()

    return run


def _sleep_on(c):
    time.sleep(300)
    try:
        c.close()
    except Exception:
        pass


def eof_server(port):
    ctx = server_ctx('srv')

    def run():
        s = listener(port)
        while True:
            try:
                c, _ = s.accept()
            except OSError:
                return
            try:
                t = ctx.wrap_socket(c, server_side=True)
                t.sendall(b'bye')
                t.close()
            except Exception:
                try:
                    c.close()
                except Exception:
                    pass

    return run


def main():
    marker = sys.argv[1] if len(sys.argv) > 1 else None
    plans = [
        (P_HTTP, http_server(P_HTTP, 'srv')),
        (P_OTHER, http_server(P_OTHER, 'other')),
        (P_STARTTLS, starttls_server(P_STARTTLS)),
        (P_EARLY, early_server(P_EARLY)),
        (P_BLACKHOLE, blackhole_server(P_BLACKHOLE)),
        (P_EOF, eof_server(P_EOF)),
        (P_SELF, http_server(P_SELF, 'ss')),
    ]
    threads = []
    for port, run in plans:
        t = threading.Thread(target=run, daemon=True)
        t.start()
        threads.append(t)
    if marker:
        with open(marker, 'w') as f:
            f.write('ready\n')
    threading.Event().wait()


if __name__ == '__main__':
    main()
