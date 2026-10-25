// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// uuid: RFC 9562 version-4 UUIDs from the OS CSPRNG.
//
//     use 'uuid.fun';
//     ?. UUID();   // 4f3c2b1a-9d8e-4f7a-8b6c-0123456789ab
//
// Random bytes come from getentropy() on Unix and RtlGenRandom
// (advapi32.SystemFunction036) on Windows. On a Unix whose libc predates
// getentropy() (glibc < 2.25, macOS < 10.12) the bytes are read from
// /dev/urandom instead. There is no seeding, no global state, and no
// userspace pseudo-random fallback: UUID() raises when the OS source is
// unavailable.
use 'lib-host.fun';

var _isWin = IsWindows();
var _rand = nil;
var _randWin = false;
var _randFile = false;
var _open = nil;
var _read = nil;
var _close = nil;

if _isWin then
  _randWin = true;
  try
    _rand = 'advapi32'.getapi('SystemFunction036', 'pi:i');
  except
    _rand = nil;
  end try;
else
  try
    _rand = LibC().getapi('getentropy', 'pi:i');
  except
    _rand = nil;
  end try;
  if _rand = nil then
    // glibc < 2.25 has no getentropy(); read the kernel CSPRNG directly.
    try
      _open  = LibC().getapi('open',  'sii:i');
      _read  = LibC().getapi('read',  'ipl:l');
      _close = LibC().getapi('close', 'i:i');
      _randFile = true;
    except
      _randFile = false;
    end try;
  end if;
end if;

var _hex = '0123456789abcdef';

fun _rand16()
  result = '';
  if _rand = nil and not _randFile then
    raise 'uuid: OS random source is not available';
  end if;
  var b = 0.toChar().x(16);
  if _randWin then
    if _rand(b.toNum(-1), 16) = 0 then
      raise 'uuid: RtlGenRandom failed';
    end if;
  elsif _rand <> nil then
    if _rand(b.toNum(-1), 16) <> 0 then
      raise 'uuid: getentropy failed';
    end if;
  else
    var fd = _open('/dev/urandom', 0, 0);
    if fd < 0 then
      raise 'uuid: /dev/urandom is not available';
    end if;
    var got = 0;
    while got < 16 do
      var n = _read(fd, b.toNum(-1) + got, 16 - got);
      if n <= 0 then
        _close(fd);
        raise 'uuid: /dev/urandom read failed';
      end if;
      got += n;
    end do;
    _close(fd);
  end if;
  result = b;
end fun;

fun _byteHex(v)
  result = _hex.substr(v >> 4, 1) & _hex.substr(v bit and 15, 1);
end fun;

fun UUID()
  var b = _rand16();
  var h = '';
  for i = 0 to 15 do
    var v = b.toByte(i);
    if i = 6 then
      v = (v bit and 0x0f) bit or 0x40;   // version 4
    elsif i = 8 then
      v = (v bit and 0x3f) bit or 0x80;   // variant 10xx
    end if;
    h &= _byteHex(v);
  end do;
  result = h.substr(0, 8) & '-' & h.substr(8, 4) & '-' & h.substr(12, 4) &
           '-' & h.substr(16, 4) & '-' & h.substr(20, 12);
end fun;
