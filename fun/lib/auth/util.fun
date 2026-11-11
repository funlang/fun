// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// auth/util: internal HMAC-SHA256, Base64URL and byte comparison helpers for
// signed cookies (and JWT later). SHA256 comes from lib-md5, so there is no
// extra native dependency: normal builds use the host hash backend and safe
// builds fall back to the pure Fun implementation.

use '../lib-base64.fun';
use '../lib-host.fun';
use '../lib-md5.fun';
use '../lib-utils.fun';

var _AUTH_B64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
var _AUTH_SHA256 = 32780;
var _AUTH_SHA384 = 32781;
var _AUTH_SHA512 = 32782;
var _authCr = nil;
var _authTime = nil;

fun _authCrypt()
  if _authCr <> nil then result = _authCr; return; end if;
  var host = 'host'.arg().getJson(fd: true);
  try
    if host.os = 'linux' or host.os = 'macos' then
      use '../lib-crypt-unx.fun' as libCr;
      _authCr = libCr;
    else
      use '../lib-crypt.fun' as libCr;
      _authCr = libCr;
    end if;
  except
    raise 'auth: crypto backend is not available';
  end try;
  result = _authCr;
end fun;

fun _authHashHex(msg, alg)
  if alg = 'sha256' then result = SHA256(msg); return; end if;
  var c = _authCrypt();
  if alg = 'sha384' then
    result = c.Crypt(msg, _AUTH_SHA384);
  elsif alg = 'sha512' then
    result = c.Crypt(msg, _AUTH_SHA512);
  else
    raise 'auth: unsupported hash: ' & alg;
  end if;
end fun;

var _authCngOpen = nil;
var _authCngClose = nil;
var _authCngHash = nil;

fun _authCngName(name)
  var host = 'host'.arg().getJson(fd: true);
  if host.chars = 2 then
    result = name & 0.toChar();
    return;
  end if;
  var out = '';
  var i = 0;
  while i < name.length() do
    out &= name[i] & 0.toChar();
    i += 1;
  end do;
  result = out & 0.toChar();
end fun;

fun _authCngHmac(key, msg, alg)
  if _authCngOpen = nil then
    _authCngOpen  = 'bcrypt.dll'.getapi('BCryptOpenAlgorithmProvider', 'pppi:i');
    _authCngClose = 'bcrypt.dll'.getapi('BCryptCloseAlgorithmProvider', 'pi:i');
    _authCngHash  = 'bcrypt.dll'.getapi('BCryptHash', 'ppipipi:i');
  end if;
  var name = 'SHA384';
  var len = 48;
  if alg = 'sha512' then name = 'SHA512'; len = 64; end if;
  var wn = _authCngName(name);
  var h = 0;
  var st = _authCngOpen(var h, wn.toNum(-1), 0, 8);
  if st <> 0 then raise 'auth: CNG open failed (' & st & ')'; end if;
  try
    var buf = ' '.x(len);
    st = _authCngHash(h, key.toNum(-1), key.length(), msg.toNum(-1), msg.length(), buf.toNum(-1), len);
    if st <> 0 then raise 'auth: CNG hash failed (' & st & ')'; end if;
    var raw = 0.toChar().x(len);
    var i = 0;
    while i < len do
      raw.fromByte(i, buf.toByte(i));
      i += 1;
    end do;
    result = raw;
  finally
    _authCngClose(h, 0);
  end try;
end fun;

fun AuthHmacRaw(key, msg, alg)
  if alg <> 'sha256' and 'host'.arg().getJson(fd: true).os = 'windows' then
    result = _authCngHmac(key, msg, alg);
    return;
  end if;
  var block = 64;
  if alg = 'sha384' or alg = 'sha512' then block = 128; end if;
  if key.length() > block then key = hex2str(_authHashHex(key, alg)); end if;
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
  result = hex2str(_authHashHex(opad & hex2str(_authHashHex(ipad & msg, alg)), alg));
end fun;

fun AuthHmacHex(key, msg, alg)
  result = str2hex(AuthHmacRaw(key, msg, alg));
end fun;

fun AuthHmacSha256Raw(key, msg)
  result = AuthHmacRaw(key, msg, 'sha256');
end fun;

fun AuthHmacSha256Hex(key, msg)
  result = str2hex(AuthHmacSha256Raw(key, msg));
end fun;

fun AuthUnixNow()
  if _authTime <> nil then result = _authTime(0); return; end if;
  var host = 'host'.arg().getJson(fd: true);
  if host.os = 'windows' then
    try
      _authTime = LibC().getapi('_time64', 'p:l');
    except
      _authTime = LibC().getapi('time', 'p:l');
    end try;
  else
    _authTime = LibC().getapi('time', 'p:l');
  end if;
  result = _authTime(0);
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
