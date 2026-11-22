// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// Worker entry points used by lib-worker-test.fun. Kept in a separate file so
// every test worker parses a fresh copy, exactly like a real worker module.

use 'fun/lib/lib-worker.fun';

fun sum(payload)
  var args = payload.getJson(fd: true);
  var n = args[0].toNum();
  var s = 0;
  for i = 1 to n do s += i; end do;
  result = '' & s;
end fun;

fun echo(payload)
  result = payload;
end fun;

fun fail(payload)
  raise 'worker boom';
end fun;

// workerMap wraps each item as [item], so payload.getJson(fd: true) is
// [[a, b]] here. Return [a + b] so workerMap can unwrap [0].
fun fdadd(payload)
  var args = payload.getJson(fd: true);
  var pair = args[0];
  result = (new [pair[0] + pair[1]]).@toJson(fd: true);
end fun;

fun slow(payload)
  var s = 0;
  for i = 1 to 3000000 do s += i mod 3; end do;
  result = '' & s;
end fun;

// Long-running loop used by cancel tests. 30M iterations is a few seconds, so
// a working cancel returns much sooner; the bound only keeps a broken cancel
// from hanging the suite forever.
fun spin(payload)
  var n = 0;
  var limit = payload.toNum();
  if limit < 1 then limit = 30000000; end if;
  while n < limit do n += 1; end do;
  result = '' & n;
end fun;

// Same loop inside try/except. ECancelled is not a normal script error, so the
// handler must not swallow it and the worker must still stop.
fun spinCatch(payload)
  var n = 0;
  var limit = payload.toNum();
  if limit < 1 then limit = 30000000; end if;
  try
    while n < limit do n += 1; end do;
  except
    // A cancel must bypass this handler.
  end try;
  result = '' & n;
end fun;

// Blocks in a named channel. recv(-1) is a cancellation safe point.
fun waitChannel(payload)
  var ch = Channel(payload);
  var v = ch.recv(-1);
  result = '' & (v = nil);
end fun;

// Module-level state: a pool slot keeps this across jobs, a one-shot worker
// rebuilds it. Used to prove resident slots really are resident.
var hits = 0;
fun bumpGlobal(payload)
  hits += 1;
  result = '' & hits;
end fun;

// Smaller add pair for poolMap.
fun fdadd2(payload)
  var args = payload.getJson(fd: true);
  var pair = args[0];
  result = (new [pair[0] + pair[1]]).@toJson(fd: true);
end fun;

// Concurrent regex use: every worker shares the process-wide PCRE pattern
// cache, so this exercises its lock (and the JIT upgrade on second use).
fun regexHammer(payload)
  var n = payload.toNum();
  var sum = 0;
  var i = 0;
  while i < n loop
    var s = 'a1b22c333';
    if s.match(/\d+/g) <> nil then sum += 1; end if;
    var r = ('(\d+)' & (i mod 7)).toRegex('g');
    sum += s.replace(r, '#').length();
    i += 1;
  end loop;
  result = '' & sum;
end fun;

// Producer: put 1..n into a named channel carried in the payload.
fun sendN(payload)
  var args = payload.getJson(fd: true);
  var ch = Channel(args[0]);
  var n = args[1].toNum();
  for i = 1 to n do ch.send('' & i); end do;
  result = '' & n;
end fun;

// Consumer: read n values from a named channel and return their sum.
fun recvN(payload)
  var args = payload.getJson(fd: true);
  var ch = Channel(args[0]);
  var n = args[1].toNum();
  var s = 0;
  for i = 1 to n do
    var v = ch.recv(-1);
    if v <> nil then s += v.toNum(); end if;
  end do;
  result = '' & s;
end fun;
