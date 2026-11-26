// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// uuid: RFC 9562 version-4 and version-7 UUIDs from the OS CSPRNG.
//
//     use 'uuid.fun';
//     ?. UUID();   // 4f3c2b1a-9d8e-4f7a-8b6c-0123456789ab
//     ?. UUID7();  // 0192a3b4-c5d6-7e8f-9a0b-1c2d3e4f5a6b
//
// Random bytes come from getentropy() on Unix and RtlGenRandom
// (advapi32.SystemFunction036) on Windows. On a Unix whose libc predates
// getentropy() (glibc < 2.25, macOS < 10.12) the bytes are read from
// /dev/urandom instead. There is no seeding, no global state, and no
// userspace pseudo-random fallback: both UUID() and UUID7() raise when the OS
// source is unavailable.
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

// The largest timestamp that fits into the 48-bit UUIDv7 field.
var _uuidMaxMs = 281474976710655;   // 2^48 - 1

// unixMs is valid only as an integer inside the 48-bit field.
fun _uuidMsOk(unixMs)
  if unixMs.type() <> 3 then result = false; return; end if;
  if unixMs < 0 or unixMs > _uuidMaxMs then result = false; return; end if;
  result = true;
end fun;

// The 48-bit timestamp as 12 hex characters, big-endian.
// Shifts only see the low 32 bits in Fun, so the top two bytes come from
// division instead.
fun _uuidTimeHex(ts)
  result = _byteHex(ts div 1099511627776) &        // 2^40
           _byteHex((ts div 4294967296) mod 256) & // 2^32
           _byteHex((ts div 16777216) mod 256) &   // 2^24
           _byteHex((ts div 65536) mod 256) &      // 2^16
           _byteHex((ts div 256) mod 256) &
           _byteHex(ts mod 256);
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

// RFC 9562 version-7 UUID: the leading 48 bits hold a Unix millisecond
// timestamp (big-endian), so generated UUIDs are roughly time-ordered. The
// remaining 74 bits are random, from the same OS source as UUID().
//
//   UUID7();              // from the host wall clock
//   UUID7(1700000000123); // pinned timestamp, for tests or imported data
//
// unixMs must be an integer in 0 .. 2^48 - 1. Omitting the argument consults
// HostUnixMs(); there is no fallback to UUID(), pseudo-random or a stale local
// time when the host clock is unavailable.
fun UUID7(unixMs)
  var ts = unixMs;
  // 0 is a valid timestamp, so the missing argument is detected by type: an
  // omitted argument is nil (type 0) while 0 is an integer (type 3).
  if ts.type() = 0 then
    ts = HostUnixMs();
  elsif not _uuidMsOk(ts) then
    raise 'uuid7: unixMs must be an integer in 0 .. 2^48 - 1';
  end if;
  var b = _rand16();
  // bytes 0..5 carry the timestamp; the random bytes fill the version,
  // variant and remaining entropy fields, so only one CSPRNG read is needed.
  var h = _uuidTimeHex(ts);
  for i = 6 to 15 do
    var v = b.toByte(i);
    if i = 6 then
      v = (v bit and 0x0f) bit or 0x70;   // version 7
    elsif i = 8 then
      v = (v bit and 0x3f) bit or 0x80;   // variant 10xx
    end if;
    h &= _byteHex(v);
  end do;
  result = h.substr(0, 8) & '-' & h.substr(8, 4) & '-' & h.substr(12, 4) &
           '-' & h.substr(16, 4) & '-' & h.substr(20, 12);
end fun;
