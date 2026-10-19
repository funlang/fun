// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-netif-unx: network interface enumeration (Linux/macOS shared).
//
// getifaddrs(3) has the same field offsets on both hosts for everything used
// here; only the sockaddr family byte differs (Darwin keeps sa_len at [0], so
// the u16 family sits at [1]; Linux puts it at [0]).
//
// IPv4 addresses only for now. The Windows backend (GetAdaptersAddresses) is a
// follow-up: hosts resolve the neutral `use 'lib-netif.fun'` to this file, so
// user code already reads the same on Linux and macOS.

use 'lib-winsock-unx.fun';
use 'lib-host.fun';

var _getifaddrs  = LibC().getapi('getifaddrs',  'p:i');
var _freeifaddrs = LibC().getapi('freeifaddrs', 'p:v');

// NUL-terminated C string at pointer p (interface names are <= 16 bytes).
fun _ni_str(p)
  var b = 0.toChar().x(64);
  _memcpy(b.toNum(-1), p, 64);
  var n = 0;
  while n < 64 and b.toByte(n) <> 0 do n += 1; end do;
  result = b.substr(0, n);
end fun;

// All IPv4 interface addresses as sets:
//   [name: 'en0', ip: '192.168.1.23', family: 2, up: true, loopback: false]
// struct ifaddrs (64-bit on both hosts): next@0 name@8 flags@16 addr@24 ...
fun Netif()
  result = new [];
  var head = 0.toChar().x(8);
  if _getifaddrs(head.toNum(-1)) <> 0 then
    raise 'lib-netif-unx: getifaddrs failed: ' & ErrMsg();
  end if;
  var first = ReadU64(head, 0);
  var p = first;
  while p <> 0 do
    var node = 0.toChar().x(56);
    _memcpy(node.toNum(-1), p, 56);
    var sa = ReadU64(node, 24);
    if sa <> 0 then
      var sb = 0.toChar().x(16);
      _memcpy(sb.toNum(-1), sa, 16);
      var fam = sb.toByte(0);
      if IsMac() then fam = sb.toByte(1); end if;
      if fam = 2 then
        result.@add([
          name:     _ni_str(ReadU64(node, 8)),
          ip:       '' & sb.toByte(4) & '.' & sb.toByte(5) & '.' &
                         sb.toByte(6) & '.' & sb.toByte(7),
          family:   fam,
          up:       (node.toByte(16) bit and 1) <> 0,   // IFF_UP
          loopback: (node.toByte(16) bit and 8) <> 0]); // IFF_LOOPBACK
      end if;
    end if;
    p = ReadU64(node, 0);
  end do;
  _freeifaddrs(first);
end fun;
