// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-url: URL encoding helpers.
//
// PercentEncode follows RFC 3986's unreserved set (ALPHA / DIGIT / "-" / "."
// / "_" / "~"), which is what Aliyun and most signed APIs expect.
//
// UrlEncode follows PHP's urlencode(): space becomes '+', and '~' is escaped.
// Use it only where the PHP behaviour must be reproduced byte for byte.
//
//     use 'lib-url.fun';
//     PercentEncode('a b*~');   // a%20b%2A~
//     UrlEncode('a b~');        // a+b%7E

var _hex = '0123456789ABCDEF';

fun _pct(s, spacePlus, tildeSafe)
  result = '';
  for i = 0 to s.length() - 1 do
    var b = s.toByte(i);
    if b >= 0x30 and b <= 0x39 or
       b >= 0x41 and b <= 0x5a or
       b >= 0x61 and b <= 0x7a or
       b = 0x2d or b = 0x2e or b = 0x5f or
       (tildeSafe and b = 0x7e) then
      result &= b.toChar();
    elsif b = 0x20 and spacePlus then
      result &= '+';
    else
      result &= '%' & _hex[b >> 4] & _hex[b bit and 0x0f];
    end if;
  end do;
end fun;

fun PercentEncode(s)
  result = _pct(s, false, true);
end fun;

fun UrlEncode(s)
  result = _pct(s, true, false);
end fun;
