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
