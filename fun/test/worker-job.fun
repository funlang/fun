// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// Worker entry points used by lib-worker-test.fun. Kept in a separate file so
// every test worker parses a fresh copy, exactly like a real worker module.

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
