// lib-netif: every host has a loopback IPv4 address, so the enumeration must
// see it (structure only: interface names and addresses are host-specific, so
// the assertions are booleans and the snapshot is stable across hosts).
use 'fun/lib/lib-netif.fun';

var xs = Netif();
?. 'count > 0: ' & (xs.@count() > 0);

var named  = false;
var loSeen = false;
var dotted = false;
var upAny  = false;
var lbFlag = false;
for x in xs do
  if x.name <> '' then named = true; end if;
  if x.ip = '127.0.0.1' then loSeen = true; end if;
  if x.ip =~ %^\d+\.\d+\.\d+\.\d+$% then dotted = true; end if;
  if x.up then upAny = true; end if;
  if x.loopback and x.ip = '127.0.0.1' then lbFlag = true; end if;
end do;
?. 'names non-empty: ' & named;
?. 'loopback address seen: ' & loSeen;
?. 'ipv4 dotted: ' & dotted;
?. 'an iface is up: ' & upAny;
?. 'loopback flag on 127.0.0.1: ' & lbFlag;
