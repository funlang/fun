// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// http-client: the HTTP client, with the same platform-neutral path as
// http-server. The `use` below re-exports the host's lib-ajax backend
// (COM on Windows, libcurl on Linux/macOS).
//
//     use 'fun/lib/http-client.fun';
//
//     var r = HttpClient([url: 'http://127.0.0.1:8080/users/42', method: 'GET']);
//     if r.code = 200 then ?. r.body; end if;
//
// HttpClient(args) performs one blocking request (url, body, method, headers,
// timeouts, proxy, ...) and returns [rc, code, message, headers, body]. The
// lib-ajax-compatible class Ajax is re-exported too. Http(args) lives in the
// host's lib-ajax backend -- lib-ajax-unx.fun on Linux/macOS, lib-ajax.fun on
// Windows -- and returns a set [rc, code, message, headers, body].

use 'lib-ajax.fun';

fun HttpClient(args)
  result = Http(args);
end fun;
