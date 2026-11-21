// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// Worker entry used by the Shared test. Every worker opens the named store
// carried in the payload, so the counter is shared without passing a Fun object
// between threads.

use 'fun/lib/lib-worker.fun';

fun bump(payload)
  var name = payload.getJson(fd: true)[0];
  var n = Shared(name).add('n', 1);
  result = (new [n]).@toJson(fd: true);
end fun;
