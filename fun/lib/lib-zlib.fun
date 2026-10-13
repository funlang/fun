// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-utils.fun';
use 'lib-math.fun';

// lib-zlib: zlib (deflate/inflate) on Windows, Linux and macOS.
//
// The algorithm is identical on all hosts; only three things differ, so they
// are resolved once at load time instead of splitting the module:
//   1. the library name ('zlib.dll' / 'libz.so.1' / 'libz.1.dylib');
//   2. the z_stream layout: 56 bytes / 4-byte fields on Win32, 112 bytes with
//      8-byte pointers and uLong on Linux/macOS x86_64/aarch64;
//   3. how an OUT buffer is passed. On unix the FFI hands C a temporary copy
//      of a Fun string, so the real address must be passed as a number
//      (`buf.toNum(-1)`); on Windows the plain string already is the buffer.
//      `_zp()` returns whichever form this host needs.

var _zlib_facts = 'host'.arg().getJson(fd: true);
var _zlib_unix  = _zlib_facts.os = 'linux' or _zlib_facts.os = 'macos';
var _zlib_mac   = _zlib_facts.os = 'macos';
var _zlib_ptr   = _zlib_facts.bits div 8;

var ZLIB_VERSION = "1.2.11";
var ZLIB_SIZE    = 14 * 4;
var ZLIB_MAX     = 2 ^ 30;
var ZLIB_BLOCK   = 256*1024;
var zlibdll = 'zlib.dll';
var zlib = nil;
if _zlib_unix then
  if _zlib_mac then zlibdll = 'libz.1.dylib'; else zlibdll = 'libz.so.1'; end if;
  ZLIB_SIZE = 112;          // sizeof(z_stream) on LP64
end if;
try
  if _zlib_unix then
    zlib = [
      compress:     zlibdll.getapi('compress',      'ppsi:i'),
      uncompress:   zlibdll.getapi('uncompress',    'ppsi:i'),
      deflateInit2: zlibdll.getapi('deflateInit2_', 'piiiiisi:i'),
      deflate:      zlibdll.getapi('deflate',       'pi:i'),
      deflateEnd:   zlibdll.getapi('deflateEnd',    'p:i'),
      inflateInit2: zlibdll.getapi('inflateInit2_', 'pisi:i'),
      inflate:      zlibdll.getapi('inflate',       'pi:i'),
      inflateEnd:   zlibdll.getapi('inflateEnd',    'p:i'),
    ];
  else
    zlib = [
      compress:     zlibdll.getapi('compress',      'spsi:i'),
      uncompress:   zlibdll.getapi('uncompress',    'spsi:i'),
      deflateInit2: zlibdll.getapi('deflateInit2_', 'siiiiisi:i'),
      deflate:      zlibdll.getapi('deflate',       'si:i'),
      deflateEnd:   zlibdll.getapi('deflateEnd',    's:i'),
      inflateInit2: zlibdll.getapi('inflateInit2_', 'sisi:i'),
      inflate:      zlibdll.getapi('inflate',       'si:i'),
      inflateEnd:   zlibdll.getapi('inflateEnd',    's:i'),
    ];
  end if;
except ?. @;
end try;

// zlib's compressBound() formula; computed here so the Windows getapi map stays
// byte-identical to the original (no extra symbol to resolve).
fun _bound(n)
  result = n + (n >> 12) + (n >> 14) + (n >> 25) + 13;
end fun;

// OUT-buffer argument: the real address on unix, the plain string on Windows.
fun _zp(x)
  result = x;
  if _zlib_unix then result = x.toNum(-1); end if;
end fun;

// Pointer-width little-endian pack/unpack. lib-utils' int2str/str2int are
// fixed at 4 bytes (Fun's >> is 32-bit); a uLongf*/z_stream* field is 8 bytes
// on LP64 and addresses live above 4GB, so div/mod by 256 is used instead.
fun _zw(v)
  result = '';
  var u = v;
  for i = 0 to _zlib_ptr - 1 do
    result &= (u mod 256).toChar();
    u = u div 256;
  end do;
end fun;

fun _zr(s, off)
  result = 0;
  var m = 1;
  for i = 0 to _zlib_ptr - 1 do
    result += s.toByte(off + i) * m;
    m *= 256;
  end do;
end fun;

fun compress(s, noheader)
  result = s;
  if zlib then
    var bound = _bound(s.length());
    var r = 0.toChar().x(bound);
    var l = _zw(bound);
    var ret = zlib.compress(_zp(r), _zp(l), s, s.length());
    if ret = 0 then
      result = r.substr(len: _zr(l, 0));
      if noheader then
        result = (result.toByte(2) bit and 0xfe).toChar() & result.substr(3, -7) & '\x00\x00\xff\xff'.escape();
      end if;
    else ?, 'compress error:'; ?. ret;
    end if;
  end if;
end fun;

fun decompress(s, length)
  result = s;
  if zlib then
    // zlib's uncompress rejects a zero-capacity destination (Z_BUF_ERROR) even
    // when the stream inflates to nothing, so keep at least one byte.
    var cap = length;
    if cap = 0 then cap = 1; end if;
    var r = 0.toChar().x(cap);
    var l = _zw(cap);
    var ret = zlib.uncompress(_zp(r), _zp(l), s, s.length());
    if ret = 0 then
      result = r.substr(len: _zr(l, 0));
    else ?, 'decompress error:'; ?. ret;
    end if;
  end if;
end fun;

var @PI = 0;  // ptr of in,  next_in
var @LI = 4;  // len of in,  avail_in (uInt, always 4 bytes)
var @PO = 12; // ptr of out, next_out
var @LO = 16; // len of out, avail_out (uInt, always 4 bytes)
var @LA = 20; // len of all, total_out (uLong, pointer width)
if _zlib_unix then
  @PI = 0; @LI = 8; @PO = 24; @LO = 32; @LA = 40;
end if;

fun flate(s, inde, args, init)
  result = '';
  var zs = args?.zs? or 0.toChar().x(ZLIB_SIZE);
  var zp = zs.toNum(-1);
  _zw(s.toNum(-1))        .move(@PI+zp);
  int2str(s.length())     .move(@LI+zp);
  var ret = init and not args?.dontInit? and init(_zp(zs));
  var r = 0.toChar().x(ZLIB_BLOCK);
  var lr = 0;
  loop
    // Provide an output buffer whenever the previous one is full. This must
    // NOT be gated on "input remains": with empty input (or a final flush)
    // there is no input left but zlib still has to emit the end-of-stream
    // bytes. Gating on `avail_in > 0` made deflate('')/inflate('') emit
    // nothing (and diverge from zlib's 2-byte empty raw stream).
    if str2int(zs, @LO) = 0 then
      _zw(r.toNum(-1))     .move(@PO+zp);
      int2str(ZLIB_BLOCK) .move(@LO+zp);
    end if;
    var       all = _zr(zs, @LA);
    if all > lr then
      result &= args?.rs?.Write?(r, all - lr) or r.substr(len: all - lr);
      lr = all;
    end if;
    ret = zlib[inde & 'flate'].call(_zp(zs), not args?.ws? and 4 or 0);
    //?, ret; ?. echoBuff(zs);
    exit when all = _zr(zs, @LA);
  end loop;
  ret = init and not args?.dontEnd? and zlib[inde & 'flateEnd'].call(_zp(zs));
  result = args?.rs?.Get?() or result;
end fun;

fun inflate(s, args)
  result = flate(s, 'in', args, zs -> zlib.inflateInit2(_zp(zs), -15, ZLIB_VERSION, ZLIB_SIZE));
end fun;

fun deflate(s, level, args) // ws frame for chrome
  result = flate(s, 'de', args, zs -> zlib.deflateInit2(_zp(zs), level or args?.level? or -1, 8, -15, 8, 0, ZLIB_VERSION, ZLIB_SIZE));
end fun;

fun echoBuff(s)
  result = str2hex(s).replace(/(?<=\w{8})/g, ' ');
end fun;
