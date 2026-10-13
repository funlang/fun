// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// lib-unicode (Unix backend): pure-Fun GBK(CP936) <-> UTF-8.
//
// Shared logic (constants, isUtf8/isGb2312, utf8toGb2312/gb2312toUtf8) lives in
// lib-unicode-base.fun; the Windows backend is lib-unicode.fun (kernel32).
// This module carries no OS FFI: the conversion table ships as
// fun/lib/gb2312.tbl (2-byte little-endian codepoints indexed by
// (lead-0x81)*191 + (trail-0x40); 0 means unmapped). CP936 is GBK, a superset of
// GB2312, matching the base's `gb2312 = 936` constant.
//
// Only the gb2312/utf8 code pages are supported here; the UTF-16/32/7 options
// raise (nothing in the tree uses them on Unix).

use 'lib-unicode-base.fun';
use ':gb2312.tbl' as _gbTbl;

fun _gbCp(lead, trail)
  result = 0;
  if lead >= 0x81 and lead <= 0xfe and trail >= 0x40 and trail <= 0xfe then
    var i = (lead - 0x81) * 191 + (trail - 0x40);
    result = _gbTbl.toByte(i * 2) + (_gbTbl.toByte(i * 2 + 1) << 8);
  end if;
end fun;

fun _u8Put(cp)
  if cp < 0x80 then
    result = cp.toChar();
  elsif cp < 0x800 then
    result = (0xc0 + (cp >> 6)).toChar() & (0x80 + (cp bit and 0x3f)).toChar();
  else
    result = (0xe0 + (cp >> 12)).toChar() &
             (0x80 + ((cp >> 6) bit and 0x3f)).toChar() &
             (0x80 + (cp bit and 0x3f)).toChar();
  end if;
end fun;

fun _u8Get(s, i)
  // `[...]` is the static array literal (element expressions are evaluated once
  // and cached), so the result is built with the dynamic form `new [...]`.
  var c  = s.toByte(i);
  var cp = 0;
  var n  = 1;
  if c < 0x80 then
    cp = c;
  elsif c < 0xe0 then
    cp = ((c bit and 0x1f) << 6) + (s.toByte(i + 1) bit and 0x3f);
    n  = 2;
  elsif c < 0xf0 then
    cp = ((c bit and 0x0f) << 12) + ((s.toByte(i + 1) bit and 0x3f) << 6) + (s.toByte(i + 2) bit and 0x3f);
    n  = 3;
  else
    cp = 0;
    n  = 4; // 4-byte sequence: outside GBK, dropped
  end if;
  result = new [cp, n];
end fun;

fun _gbToUtf8(s)
  result = '';
  var i = 0;
  while i < s.length() do
    var c = s.toByte(i);
    if c < 0x80 then
      result &= c.toChar();
      i += 1;
    else
      var cp = _gbCp(c, s.toByte(i + 1));
      if cp = 0 then
        i += 1;
      else
        result &= _u8Put(cp);
        i += 2;
      end if;
    end if;
  end do;
end fun;

var _gbRev = nil;
fun _gbRevInit()
  if _gbRev = nil then
    _gbRev = new [];
    for lead = 0x81 to 0xfe do
      for trail = 0x40 to 0xfe do
        if trail <> 0x7f then
          var cp = _gbCp(lead, trail);
          if cp <> 0 and _gbRev[cp] = nil then
            _gbRev[cp] = (lead << 8) + trail;
          end if;
        end if;
      end do;
    end do;
  end if;
end fun;

fun _utf8ToGb(s)
  _gbRevInit();
  result = '';
  var i = 0;
  while i < s.length() do
    var r = _u8Get(s, i);
    var cp = r[0];
    if cp < 0x80 then
      result &= cp.toChar();
    else
      var v = _gbRev[cp];
      if v <> nil then
        result &= (v >> 8).toChar() & (v bit and 0xff).toChar();
      end if;
    end if;
    i += r[1];
  end do;
end fun;

var Unicode = UnicodeClass();
class UnicodeClass = UnicodeBase()
  fun fromBytes(s, cp)
    if cp = gb2312 then
      result = _gbToUtf8(s.toStr());
    elsif cp = utf8 then
      result = s.toStr();
    else
      raise 'fromBytes: code page $cp is not supported on Unix'.eval();
    end if;
  end fun;

  fun toBytes(s, cp)
    if cp = gb2312 then
      result = _utf8ToGb(s.toStr());
    elsif cp = utf8 then
      result = s.toStr();
    else
      raise 'toBytes: code page $cp is not supported on Unix'.eval();
    end if;
  end fun;
end class;
