// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// tls: TLS client streams over the host system TLS library.
//
// Unix/macOS: this name dispatches to tls-unx.fun (the system libssl) via the
// platform use rules. Windows: the SChannel backend lands here in a later
// milestone; until then Windows cannot load this module.
//
//     var s = tls.connect('example.com', 443, [timeout: 10000]);
//     var fd = ConnectSocket('smtp.example.com', 587);   // lib-winsock
//     var s = tls.wrap(fd, [host: 'smtp.example.com']);
//
// Verification (certificate chain + hostname) is on by default; verify: false
// skips it. opts.timeout (ms) covers TCP connect and the handshake. Streams
// satisfy the io.Reader/io.Writer contract; close() sends close_notify.
// fun ships no crypto library of its own -- TLS always comes from the host.
use 'tls-unx.fun';
