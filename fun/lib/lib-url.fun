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

// Module globals are shared across `use`d files, so keep this name specific:
// uuid.fun also defines a module-level hex table.
var _urlHex = '0123456789ABCDEF';

fun _urlPct(s, spacePlus, tildeSafe)
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
      result &= '%' & _urlHex[b >> 4] & _urlHex[b bit and 0x0f];
    end if;
  end do;
end fun;

fun PercentEncode(s)
  result = _urlPct(s, false, true);
end fun;

fun UrlEncode(s)
  result = _urlPct(s, true, false);
end fun;
