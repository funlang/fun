// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// auth/util: internal HMAC-SHA256, Base64URL and byte comparison helpers for
// signed cookies (and JWT later). SHA256 comes from lib-md5, so there is no
// extra native dependency: normal builds use the host hash backend and safe
// builds fall back to the pure Fun implementation.

use '../lib-base64.fun';
use '../lib-md5.fun';
use '../lib-utils.fun';

var _AUTH_B64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

fun AuthHmacSha256Raw(key, msg)
  var block = 64;
  if key.length() > block then key = hex2str(SHA256(key)); end if;
  if key.length() < block then key &= 0.toChar().x(block - key.length()); end if;
  var ipad = '';
  var opad = '';
  var i = 0;
  while i < block do
    var b = key.toByte(i);
    ipad &= (b bit xor 0x36).toChar();
    opad &= (b bit xor 0x5c).toChar();
    i += 1;
  end do;
  result = hex2str(SHA256(opad & hex2str(SHA256(ipad & msg))));
end fun;

fun AuthHmacSha256Hex(key, msg)
  result = str2hex(AuthHmacSha256Raw(key, msg));
end fun;

fun AuthB64UrlEncode(s)
  var b = toBase64(s);
  var out = '';
  var i = 0;
  while i < b.length() do
    var c = b[i];
    if c = '+' then
      c = '-';
    elsif c = '/' then
      c = '_';
    elsif c = '=' then
      c = '';
    end if;
    out &= c;
    i += 1;
  end do;
  result = out;
end fun;

fun AuthB64UrlDecode(s)
  if s.type() <> 8 then raise 'auth: base64url value must be a string'; end if;
  var n = s.length();
  if n mod 4 = 1 then raise 'auth: invalid base64url length'; end if;
  var i = 0;
  var t = '';
  while i < n do
    var c = s[i];
    if _AUTH_B64URL.subpos(c) < 0 then raise 'auth: invalid base64url character'; end if;
    if c = '-' then
      c = '+';
    elsif c = '_' then
      c = '/';
    end if;
    t &= c;
    i += 1;
  end do;
  var r = n mod 4;
  if r = 2 then
    t &= '==';
  elsif r = 3 then
    t &= '=';
  end if;
  result = fromBase64(t);
end fun;

fun AuthBytesEqual(a, b)
  if a.length() <> b.length() then result = false; return; end if;
  var d = 0;
  var i = 0;
  while i < a.length() do
    d = d bit or (a.toByte(i) bit xor b.toByte(i));
    i += 1;
  end do;
  result = d = 0;
end fun;
