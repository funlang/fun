// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// io: generic stream helpers. A reader has read(n) -> string; short reads are
// allowed and '' means EOF. A writer has write(s) and must write all of s.
// Helpers never own, close or flush the underlying handle. io.buffer is the
// in-memory implementation; fs.open handles work directly; io.stdin,
// io.stdout and io.stderr adapt process stdio as byte streams. Process stdio
// needs an FFI-enabled build; io.buffer stays usable without FFI.
//
//     use 'io.fun';
//
//     var b = io.buffer('abc');
//     var all = io.readAll(b);
//     io.copy(out, b);
//     io.writeString(out, 'done');

var _IO_CHUNK = 8192;

var _ioState = new [
  bound: false,
  isWindows: false,
  isMac: false,
  isLinux: false,
  isUnicode: false,
  read: nil,
  write: nil,
  stdHandle: nil,
  readFile: nil,
  writeFile: nil,
  getLastError: nil,
  errno: nil,
  strerror: nil,
  memcpy: nil
];

fun _ioBind()
  if _ioState.bound then result = true; return; end if;
  var host = 'host'.arg().getJson(fd: true);
  _ioState.isWindows = host.os = 'windows';
  _ioState.isMac = host.os = 'macos';
  _ioState.isLinux = host.os = 'linux';
  _ioState.isUnicode = 0x1234.toChar().toByte() > 0xff;
  if not _ioState.isWindows and not _ioState.isMac and not _ioState.isLinux then
    raise 'io: unsupported host ' & host.os;
  end if;
  try
    if _ioState.isWindows then
      _ioState.stdHandle = 'kernel32'.getapi('GetStdHandle', 'i:p');
      // 'i' carries raw pointers on WinAPI 32-bit and win64 lffi; 'v' is NULL.
      _ioState.readFile = 'kernel32'.getapi('ReadFile', 'iiiiv:i');
      _ioState.writeFile = 'kernel32'.getapi('WriteFile', 'iiiiv:i');
      _ioState.getLastError = 'kernel32'.getapi('GetLastError', ':i');
    elsif _ioState.isMac then
      _ioState.read = 'libSystem.B.dylib'.getapi('read', 'ipi:i');
      _ioState.write = 'libSystem.B.dylib'.getapi('write', 'ipi:i');
      _ioState.memcpy = 'libSystem.B.dylib'.getapi('memcpy', 'ppn:p');
      _ioState.errno = 'libSystem.B.dylib'.getapi('__error', ':p');
      try
        _ioState.strerror = 'libSystem.B.dylib'.getapi('strerror', 'i:s');
      except
        _ioState.strerror = nil;
      end try;
    else
      _ioState.read = 'libc.so.6'.getapi('read', 'ipi:i');
      _ioState.write = 'libc.so.6'.getapi('write', 'ipi:i');
      _ioState.memcpy = 'libc.so.6'.getapi('memcpy', 'ppn:p');
      _ioState.errno = 'libc.so.6'.getapi('__errno_location', ':p');
      try
        _ioState.strerror = 'libc.so.6'.getapi('strerror', 'i:s');
      except
        _ioState.strerror = nil;
      end try;
    end if;
    _ioState.bound = true;
    result = true;
  except
    raise 'io: process stdio unavailable; an FFI-enabled build is required (' & @ & ')';
  end try;
end fun;

fun _ioReadSize(n)
  var t = n.type();
  if t = 0 then raise 'io: read size required'; end if;
  if t <> 3 then raise 'io: read size must be an integer'; end if;
  if n < 0 then raise 'io: read size must be >= 0'; end if;
  if n > 0x7fffffff then raise 'io: read size too large'; end if;
  result = n;
end fun;

fun _ioWriteData(v)
  var t = v.type();
  if t = 0 then
    if v <> nil then raise 'io: write data must be a string'; end if;
    result = '';
  elsif t <> 8 then
    raise 'io: write data must be a string';
  else
    result = v;
  end if;
end fun;

// byte i of a raw buffer; only needed on two-byte-char builds
fun _ioByteAt(s, i)
  result = s[i * 0.5 + 0.1];
end fun;

fun _ioBytesToString(buf, k)
  if k = 0 then result = ''; return; end if;
  if _ioState.isUnicode then
    result = '';
    for i = 0 to k - 1 do result &= _ioByteAt(buf, i).toChar(); end do;
  else
    result = buf.substr(0, k);
  end if;
end fun;

fun _ioByteData(s)
  if not _ioState.isUnicode then result = s; return; end if;
  var n = s.length();
  var b = 0.toChar().x(n);
  for i = 0 to n - 1 do b.fromByte(i, s.toByte(i)); end do;
  result = b;
end fun;

fun _ioDword(s)
  if _ioState.isUnicode then
    result = (_ioByteAt(s, 3) << 24) + (_ioByteAt(s, 2) << 16) +
             (_ioByteAt(s, 1) << 8) + _ioByteAt(s, 0);
  else
    result = (s.toByte(3) << 24) + (s.toByte(2) << 16) +
             (s.toByte(1) << 8) + s.toByte(0);
  end if;
end fun;

fun _ioErrnoValue()
  var errno = _ioState.errno;
  var memcpy = _ioState.memcpy;
  if errno = nil or memcpy = nil then result = -1; return; end if;
  var p = errno();
  if p = nil then result = -1; return; end if;
  var buf = 0.toChar().x(4);
  memcpy(buf.toNum(-1), p, 4);
  result = _ioDword(buf);
end fun;

fun _ioErrnoText(e)
  if e < 0 then result = ''; return; end if;
  var strerror = _ioState.strerror;
  var s = '';
  if strerror <> nil then s = strerror(e); end if;
  if s = nil or s = '' then result = 'errno ' & e;
  else result = s & ' (' & e & ')'; end if;
end fun;

fun _ioHandle(h, what)
  if h = nil or h = 0 or h = -1 or h = 0xffffffff then
    raise 'io: ' & what & ' handle unavailable';
  end if;
  result = h;
end fun;

fun _ioReadUnix(fd, n)
  var read = _ioState.read;
  var buf = 0.toChar().x(n);
  loop
    var k = read(fd, buf.toNum(-1), n);
    var t = k.type();
    if t = 0 then raise 'io: read failed'; end if;
    if k < 0 then
      var e = _ioErrnoValue();
      if e <> 4 then
        if e < 0 then raise 'io: read failed'; end if;
        raise 'io: read failed (' & _ioErrnoText(e) & ')';
      end if;
    elsif k = 0 then
      result = '';
      return;
    else
      result = _ioBytesToString(buf, k);
      return;
    end if;
  end loop;
end fun;

fun _ioReadWin(fd, n)
  var stdHandle = _ioState.stdHandle;
  var readFile = _ioState.readFile;
  var lastError = _ioState.getLastError;
  var h = _ioHandle(stdHandle(-10), 'stdin');
  var buf = 0.toChar().x(n);
  var glen = 4;
  if _ioState.isUnicode then glen = 2; end if;
  var got = 0.toChar().x(glen);
  var ok = readFile(h, buf.toNum(-1), n, got.toNum(-1), nil);
  if ok = 0 then
    var err = lastError();
    if err = 109 or err = 38 then result = ''; return; end if;
    raise 'io: stdin read failed (' & err & ')';
  end if;
  result = _ioBytesToString(buf, _ioDword(got));
end fun;

fun _ioReadFd(fd, n)
  if fd <> 0 then raise 'io: invalid stdin fd'; end if;
  _ioBind();
  if _ioState.isWindows then result = _ioReadWin(fd, n); else result = _ioReadUnix(fd, n); end if;
end fun;

fun _ioWriteUnix(fd, s)
  var write = _ioState.write;
  var off = 0;
  var l = s.length();
  while off < l do
    var part = _ioByteData(s.substr(off));
    var blen = part.length();
    var k = write(fd, part.toNum(-1), blen);
    var t = k.type();
    if t = 0 then raise 'io: write failed'; end if;
    if k < 0 then
      var e = _ioErrnoValue();
      if e <> 4 then
        if e < 0 then raise 'io: write failed'; end if;
        raise 'io: write failed (' & _ioErrnoText(e) & ')';
      end if;
    elsif k = 0 then
      raise 'io: write failed';
    else
      off += k;
    end if;
  end do;
  result = l;
end fun;

fun _ioWriteWin(fd, s)
  var stdHandle = _ioState.stdHandle;
  var writeFile = _ioState.writeFile;
  var lastError = _ioState.getLastError;
  var id = -12;
  var what = 'stderr';
  if fd = 1 then
    id = -11;
    what = 'stdout';
  end if;
  var h = _ioHandle(stdHandle(id), what);
  var off = 0;
  var l = s.length();
  var glen = 4;
  if _ioState.isUnicode then glen = 2; end if;
  var got = 0.toChar().x(glen);
  while off < l do
    var part = _ioByteData(s.substr(off));
    var blen = part.length();
    var ok = writeFile(h, part.toNum(-1), blen, got.toNum(-1), nil);
    if ok = 0 then
      var err = lastError();
      raise 'io: write failed (' & err & ')';
    end if;
    var k = _ioDword(got);
    if k = 0 then raise 'io: write failed'; end if;
    off += k;
  end do;
  result = l;
end fun;

fun _ioWriteFd(fd, s)
  if fd <> 1 and fd <> 2 then raise 'io: invalid output fd'; end if;
  _ioBind();
  if _ioState.isWindows then result = _ioWriteWin(fd, s); else result = _ioWriteUnix(fd, s); end if;
end fun;

class _IoBuffer(s)
  var data = '';
  var pos = 0;
  var t = s.type();
  if t = 0 then
    if s <> nil then raise 'io: buffer text must be a string'; end if;
  elsif t = 8 then
    data = s;
  else
    raise 'io: buffer text must be a string';
  end if;

  fun read(n)
    n = _ioReadSize(n);
    var left = this.data.length() - this.pos;
    if n > left then n = left; end if;
    if n = 0 then result = ''; return; end if;
    result = this.data.substr(this.pos, n);
    this.pos += n;
  end fun;

  fun write(v)
    var t = v.type();
    if t = 0 then
      if v <> nil then raise 'io: write data must be a string'; end if;
    elsif t <> 8 then
      raise 'io: write data must be a string';
    end if;
    var s = v;
    if s = nil then s = ''; end if;
    this.data &= s;
    result = s.length();
  end fun;

  fun text()
    result = this.data.substr(this.pos);
  end fun;

  fun length()
    result = this.data.length() - this.pos;
  end fun;

  fun reset()
    this.data = '';
    this.pos = 0;
    result = true;
  end fun;
end class;

class _IoStdin()
  fun read(n)
    var sz = _ioReadSize(n);
    if sz = 0 then result = ''; return; end if;
    result = _ioReadFd(0, sz);
  end fun;
end class;

class _IoWriter(fd)
  var fd = fd;

  fun write(s)
    var data = _ioWriteData(s);
    if data = '' then result = 0; return; end if;
    _ioWriteFd(this.fd, data);
    result = data.length();
  end fun;
end class;

class _IoApi()
  fun buffer(text)
    result = _IoBuffer(text);
  end fun;

  fun stdin()
    result = _IoStdin();
  end fun;

  fun stdout()
    result = _IoWriter(1);
  end fun;

  fun stderr()
    result = _IoWriter(2);
  end fun;

  fun readAll(r)
    var out = new [];
    loop
      var s = r.read(_IO_CHUNK);
      if s = nil or s = '' then exit; end if;
      out.@add(s);
    end loop;
    if out.@count() = 0 then result = ''; return; end if;
    result = out.@toJson(-1);
  end fun;

  fun copy(dst, src)
    var n = 0;
    loop
      var s = src.read(_IO_CHUNK);
      if s = nil or s = '' then exit; end if;
      dst.write(s);
      n += s.length();
    end loop;
    result = n;
  end fun;

  fun writeString(w, s)
    var t = s.type();
    if t = 0 then
      if s <> nil then raise 'io: write data must be a string'; end if;
      s = '';
    elsif t <> 8 then
      raise 'io: write data must be a string';
    end if;
    w.write(s);
    result = s.length();
  end fun;
end class;

var io = _IoApi();
