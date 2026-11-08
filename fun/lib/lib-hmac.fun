// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-hmac: HMAC built on the interpreter's hash built-ins.
//
// The built-in str.sha1() returns lower-case hex, which is convenient for
// signatures but not for HMAC (which needs the raw digest as inner input).
// hex2str() from lib-utils supplies the missing conversion, so no native
// crypto dependency is needed and the module works on every host.
//
//     use 'lib-hmac.fun';
//     var raw = HmacSha1('key', 'message');       // raw 20 bytes
//     var hex = HmacSha1Hex('key', 'message');    // 40 hex chars

use 'lib-utils.fun';

fun _hmacRaw(hash, key, msg)
  var block = 64;
  if key.length() > block then
    key = hex2str(hash(key));
  end if;
  if key.length() < block then
    key &= 0.toChar().x(block - key.length());
  end if;
  var ipad = '';
  var opad = '';
  for i = 0 to block - 1 do
    var b = key.toByte(i);
    ipad &= (b bit xor 0x36).toChar();
    opad &= (b bit xor 0x5c).toChar();
  end do;
  result = hex2str(hash(opad & hex2str(hash(ipad & msg))));
end fun;

fun HmacSha1(key, msg)
  result = _hmacRaw(fun(s){result = s.sha1();}, key, msg);
end fun;

fun HmacSha1Hex(key, msg)
  result = str2hex(HmacSha1(key, msg));
end fun;
