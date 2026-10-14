// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

var cs64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
var ct64 = nil;

var Hex2Base64(s) = toBase64(s, 2);
var Str2Base64(s) = toBase64(s);

fun toBase64(s, by)
  result = '';
  by = by or 1;
  var l = s.length();
  for i = 0 to l-1 step 3 * by do
    var s3 = s.substr(i, 3 * by); //?. s3;
    var n;
    if by = 2 then
      s3 &= '0'.x(3 * by - s3.length());
      n = ('0x' & s3).toNum();
    else
      s3 &= 0.toChar().x(3 * by - s3.length());
      n = s3.toByte(0) << 16 + s3.toByte(1) << 8 + s3.toByte(2);
    end if;
    result &= cs64.substr( n >> 18,         1) &
              cs64.substr((n >> 12) mod 64, 1) &
              cs64.substr((n >> 6)  mod 64, 1) &
              cs64.substr( n        mod 64, 1)
           ;
  end do;
  l = l div by mod 3;
  if l > 0 then
    result = result.substr(len: l - 3) & '='.x(3 - l);
  end if;
end fun;

fun fromBase64(s)
  fun table(cs)
    result = new [];
    for i = 0 to 255 do
      result[i] = -1;
    end do;
    for i = 0 to cs.length() - 2 do
      result[cs.toByte(i)] = i;
    end do;
    result[cs.toByte(cs.length() - 1)] = 0; //?. result.@toJson();
  end fun;

  result = '';
  ct64 = ct64 or table(cs64);
  var l = s.length();
  for i = 0 to l-1 step 4 do
    var s4 = s.substr(i, 4); //?, s4;
    var n = ct64[s4.toByte(0)] << 18 + ct64[s4.toByte(1)] << 12 + ct64[s4.toByte(2)] << 6 + ct64[s4.toByte(3)];
    result &= ( n >> 16        ).toChar() &
              ((n >> 8) mod 256).toChar() &
              ( n       mod 256).toChar()
           ;
  end do;
  l = s.match(/=*+$/).@@().length(); //?. l;
  if l > 0 then
    result = result.substr(len: l * -1);
  end if;
end fun;
