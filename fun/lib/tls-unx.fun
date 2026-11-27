// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// tls-unx: the Unix/macOS backend of tls -- the host system libssl over the
// FFI. See the contract in the module docs; this file adds no cryptography:
// certificate chain, hostname checks and the CA store all stay inside libssl.
//
//     use 'tls.fun';
//     var s = tls.connect('example.com', 443, [timeout: 10000]);
//     s.write(req);
//     var data = s.read(16384);
//     s.close();
//
//     // STARTTLS shape: plain TCP first, then upgrade in place
//     var fd = ConnectSocket('smtp.example.com', 587);
//     ... plain dialogue (e.g. EHLO, STARTTLS) ...
//     var s = tls.wrap(fd, [host: 'smtp.example.com']);
//
// libssl is dlopen'd from the host: versioned sonames on Linux, explicit
// Homebrew/MacPorts paths on macOS (the bare name resolves to the system
// LibreSSL, which aborts the process on load). Without the system library
// the module still loads and reports an actionable error on first use.
//
// Streams satisfy the io.Reader/io.Writer contract: read(n) may return
// fewer bytes than asked and '' at EOF; write(data) writes everything.
// close() sends TLS close_notify and closes the socket. opts.timeout (ms)
// covers TCP connect and the TLS handshake; read/write are blocking.
// The first call ignores SIGPIPE for the process: a peer that has gone away
// then surfaces as a normal stream error instead of killing the interpreter.

use 'lib-host.fun';
use 'lib-utils.fun';

// platform socket constants (DyLib(lnx, mac)); see lib-winsock-unx for the
// SOL_SOCKET precedent
var _SOL_SOCKET   = DyLib(1, 0xffff);
var _SO_ERROR     = DyLib(4, 0x1007);
var _SO_RCVTIMEO  = DyLib(20, 0x1006);
var _SO_SNDTIMEO  = DyLib(21, 0x1005);
var _O_NONBLOCK   = DyLib(0x800, 4);
var _EINPROGRESS  = DyLib(115, 36);
var _MSG_DONTWAIT = DyLib(0x40, 0x80);
var _F_GETFL = 3;
var _F_SETFL = 4;
var _POLLOUT = 4;
var _CTRL_SNI = 55;    // SSL_CTRL_SET_TLSEXT_HOSTNAME

var _tlsState = new [
  hostKnown: false,
  bound: false,
  isMac: false,
  isLinux: false,
  ptrBytes: 4,
  lib: '',
  method: nil,
  ctxNew: nil,
  ctxFree: nil,
  sslNew: nil,
  sslFree: nil,
  setFd: nil,
  connect: nil,
  read: nil,
  write: nil,
  shutdown: nil,
  getError: nil,
  verify: nil,
  set1Host: nil,
  ctrl: nil,
  defPaths: nil,
  setVerify: nil,
  errGet: nil,
  errStr: nil,
  fcntl: nil,
  poll: nil,
  setsockopt: nil,
  getsockopt: nil,
  recv: nil,
  tcpConnect: nil,
  socket: nil,
  getaddrinfo: nil,
  freeaddrinfo: nil,
  strtoull: nil,
  closeFd: nil,
  strerror: nil,
  errnoFn: nil,
  signal: nil,
  memcpy: nil
];

fun _tlsHost()
  if _tlsState.hostKnown then result = true; return; end if;
  var host = 'host'.arg().getJson(fd: true);
  _tlsState.isMac = host.os = 'macos';
  _tlsState.isLinux = host.os = 'linux';
  _tlsState.ptrBytes = host.bits div 8;
  if not _tlsState.isMac and not _tlsState.isLinux then
    raise 'tls: unsupported host ' & host.os;
  end if;
  _tlsState.hostKnown = true;
  result = true;
end fun;

fun _tlsErrnoValue()
  var errnoFn = _tlsState.errnoFn;
  var memcpy = _tlsState.memcpy;
  if errnoFn = nil or memcpy = nil then result = -1; return; end if;
  var p = errnoFn();
  if p = nil or p = 0 then result = -1; return; end if;
  var buf = 0.toChar().x(4);
  memcpy(buf.toNum(-1), p, 4);
  result = buf.toByte(0) + buf.toByte(1) * 256 + buf.toByte(2) * 65536 + buf.toByte(3) * 16777216;
end fun;

fun _tlsErrnoText(e)
  if e < 0 then result = ''; return; end if;
  var s = '';
  if _tlsState.strerror <> nil then s = _tlsState.strerror(e); end if;
  if s = nil or s = '' then result = 'errno ' & e;
  else result = s & ' (' & e & ')'; end if;
end fun;

// --- socket layer (self-bound: lib-winsock-unx binds at module level, which
// --- the safe build must not trigger while loading this module) -----------

// read one pointer-width little-endian value; Fun arithmetic is 32-bit, so
// reassemble as big-endian hex text and parse with strtoull (the
// lib-winsock-unx ReadU64 recipe)
fun _tlsReadU64(s, off)
  var h = str2hex(s.substr(off, 8));
  var big = h.substr(14,2) & h.substr(12,2) & h.substr(10,2) & h.substr(8,2)
          & h.substr(6,2) & h.substr(4,2) & h.substr(2,2) & h.substr(0,2);
  var tb = ' '.x(20);
  ('0x' & big).move(tb.toNum(-1));
  result = _tlsState.strtoull(tb.toNum(-1), 0, 16);
end fun;

fun _tlsAddr2IP(addr)
  result = int2ip(str2int(addr.substr(4, 4)));
end fun;

fun _tlsIsIP(host)
  result = host =~ %^\d+\.\d+\.\d+\.\d+$%;
end fun;

// getaddrinfo; returns the numeric IPv4 address or raises
fun _tlsGetHostByName(name)
  if _tlsIsIP(name) then
    result = name;
    return;
  end if;
  // struct addrinfo is 48 bytes on x86_64; only ai_family/ai_socktype matter
  var hints = 0.toChar().x(48);
  int2str(2).move(hints.toNum(-1) + 4);      // AF_INET
  int2str(1).move(hints.toNum(-1) + 8);      // SOCK_STREAM
  var res = 0.toChar().x(8);
  var rc = _tlsState.getaddrinfo(name.toNum(-1), 0, hints.toNum(-1), res.toNum(-1));
  if rc <> 0 then
    raise 'cannot resolve host ' & name;
  end if;
  var p  = _tlsReadU64(res, 0);              // struct addrinfo *
  var ai = 0.toChar().x(48);
  _tlsState.memcpy(ai.toNum(-1), p, 48);
  // ai_addr offset: 24 on glibc, 32 on Darwin
  var sa = _tlsReadU64(ai, DyLib(24, 32));
  var sb = 0.toChar().x(16);
  _tlsState.memcpy(sb.toNum(-1), sa, 16);
  _tlsState.freeaddrinfo(p);
  result = _tlsAddr2IP(sb);
end fun;

// 16-byte sockaddr_in for a numeric IPv4 + port
fun _tlsAddr16(ip, port)
  port = port div 1;
  port = port >> 8 + port mod 256 << 8;
  ip = int2str(ip2int(ip));
  if _tlsState.isMac then
    // Darwin: sin_len=16, sin_family=AF_INET (offset 1), then port big-endian
    result = int2str(16 + (2 << 8) + (port << 16)) & ip & 0.toChar().x(8);
  else
    result = int2str(2 + (port << 16)) & ip & 0.toChar().x(8);
  end if;
end fun;

// probe the candidate list; '' when the host has no usable libssl
fun _tlsFindLib()
  var libs = DyLibList(
    ['libssl.so.3', 'libssl.so.1.1', 'libssl.so'],
    ['/opt/homebrew/opt/openssl/lib/libssl.dylib',
     '/usr/local/opt/openssl/lib/libssl.dylib',
     '/opt/homebrew/lib/libssl.dylib',
     '/opt/homebrew/lib/libssl.3.dylib',
     '/usr/local/lib/libssl.dylib']);
  for n in libs do
    try
      var m = n.getapi('TLS_client_method', ':p');
      if m <> 0 then result = n; return; end if;
    except
      // candidate missing or unusable, keep probing
    end try;
  end do;
  result = '';
end fun;

fun _tlsBind()
  if _tlsState.bound then result = true; return; end if;
  try
    // _tlsHost raises on a host without a Unix libssl (Windows); keep it
    // inside this try so every failure carries the "tls: TLS is unavailable"
    // prefix the safe-mode contract (and its test) relies on.
    _tlsHost();
    var lib = _tlsFindLib();
    if lib = '' then
      raise 'the system libssl is required (install OpenSSL; on macOS point DYLD_LIBRARY_PATH at the Homebrew lib dir)';
    end if;
    _tlsState.lib       = lib;
    _tlsState.method    = lib.getapi('TLS_client_method', ':p');
    _tlsState.ctxNew    = lib.getapi('SSL_CTX_new',   'p:p');
    _tlsState.ctxFree   = lib.getapi('SSL_CTX_free',  'p:v');
    _tlsState.sslNew    = lib.getapi('SSL_new',       'p:p');
    _tlsState.sslFree   = lib.getapi('SSL_free',      'p:v');
    _tlsState.setFd     = lib.getapi('SSL_set_fd',    'pi:i');
    _tlsState.connect   = lib.getapi('SSL_connect',   'p:i');
    _tlsState.read      = lib.getapi('SSL_read',      'ppi:i');
    _tlsState.write     = lib.getapi('SSL_write',     'ppi:i');
    _tlsState.shutdown  = lib.getapi('SSL_shutdown',  'p:i');
    _tlsState.getError  = lib.getapi('SSL_get_error', 'pi:i');
    _tlsState.verify    = lib.getapi('SSL_get_verify_result', 'p:l');
    _tlsState.set1Host  = lib.getapi('SSL_set1_host', 'ps:i');
    _tlsState.ctrl      = lib.getapi('SSL_ctrl',      'pilp:l');
    _tlsState.defPaths  = lib.getapi('SSL_CTX_set_default_verify_paths', 'p:i');
    _tlsState.setVerify = lib.getapi('SSL_CTX_set_verify', 'pip:v');
    _tlsState.errGet    = lib.getapi('ERR_get_error', ':l');
    _tlsState.errStr    = lib.getapi('ERR_error_string', 'lp:s');
    var sys = LibC();
    _tlsState.fcntl      = sys.getapi('fcntl', 'iii:i', variadic: 2);
    _tlsState.poll       = sys.getapi('poll',  'pip:i');
    _tlsState.setsockopt = sys.getapi('setsockopt', 'iiipi:i');
    _tlsState.getsockopt = sys.getapi('getsockopt', 'iiipp:i');
    _tlsState.recv       = sys.getapi('recv', 'ippi:i');
    _tlsState.tcpConnect = sys.getapi('connect', 'iii:i');
    _tlsState.socket     = sys.getapi('socket', 'iii:i');
    _tlsState.getaddrinfo = sys.getapi('getaddrinfo', 'iiii:i');
    _tlsState.freeaddrinfo = sys.getapi('freeaddrinfo', 'i:i');
    _tlsState.strtoull   = sys.getapi('strtoull', 'pii:l');
    _tlsState.closeFd    = sys.getapi('close', 'i:i');
    _tlsState.signal     = sys.getapi('signal', 'ii:p');
    try
      _tlsState.strerror = sys.getapi('strerror', 'i:s');
    except
      _tlsState.strerror = nil;
    end try;
    if _tlsState.isMac then
      _tlsState.errnoFn = sys.getapi('__error', ':p');
      _tlsState.memcpy  = sys.getapi('memcpy', 'ppn:p');
    else
      _tlsState.errnoFn = sys.getapi('__errno_location', ':p');
      _tlsState.memcpy  = sys.getapi('memcpy', 'ppn:p');
    end if;
    // libssl writes with write(2). When the peer has gone away, the kernel
    // raises SIGPIPE and the default action kills the interpreter before
    // SSL_read/SSL_write can return the EPIPE error, so read()/write()/close()
    // could never report it. Ignore SIGPIPE process-wide (Python and Node make
    // the same choice for socket I/O); callers see a normal Fun error instead.
    _tlsState.signal(13, 1);
    _tlsState.bound = true;
    result = true;
  except
    raise 'tls: TLS is unavailable; ' & @;
  end try;
end fun;

fun _tlsVerifyText(code)
  if code = 0 then result = ''; return; end if;
  if code = 18 or code = 19 then result = 'self-signed certificate';
  elsif code = 9 then result = 'certificate not yet valid';
  elsif code = 10 then result = 'certificate has expired';
  elsif code = 20 then result = 'unable to get local issuer certificate';
  elsif code = 21 then result = 'unable to verify the first certificate';
  elsif code = 23 then result = 'certificate revoked';
  elsif code = 62 then result = 'hostname mismatch';
  else result = 'certificate verify error ' & code; end if;
end fun;

fun _tlsSslErrText(ssl, rc)
  var e = _tlsState.getError(ssl, rc);
  if e = 1 then
    var q = _tlsState.errGet();
    if q = 0 then result = 'protocol error'; return; end if;
    result = _tlsState.errStr(q, 0);
  elsif e = 2 then result = 'want read';
  elsif e = 3 then result = 'want write';
  elsif e = 5 then
    var en = _tlsErrnoValue();
    if en <> 0 then result = _tlsErrnoText(en); else result = 'system call failure'; end if;
  elsif e = 6 then result = 'connection closed';
  else result = 'ssl error ' & e; end if;
end fun;

// socket receive/send timeouts for the connect+handshake window; cleared
// afterwards so read/write block as documented
fun _tlsSetTimeout(fd, ms)
  var tv = 0.toChar().x(_tlsState.ptrBytes * 2);
  int2str(ms div 1000).move(tv.toNum(-1));
  int2str(ms mod 1000 * 1000).move(tv.toNum(-1) + _tlsState.ptrBytes);
  _tlsState.setsockopt(fd, _SOL_SOCKET, _SO_RCVTIMEO, tv.toNum(-1), _tlsState.ptrBytes * 2);
  _tlsState.setsockopt(fd, _SOL_SOCKET, _SO_SNDTIMEO, tv.toNum(-1), _tlsState.ptrBytes * 2);
end fun;

fun _tlsClearTimeout(fd)
  var tv = 0.toChar().x(_tlsState.ptrBytes * 2);
  _tlsState.setsockopt(fd, _SOL_SOCKET, _SO_RCVTIMEO, tv.toNum(-1), _tlsState.ptrBytes * 2);
  _tlsState.setsockopt(fd, _SOL_SOCKET, _SO_SNDTIMEO, tv.toNum(-1), _tlsState.ptrBytes * 2);
end fun;

// resolve + TCP connect (non-blocking connect + poll when a timeout is set)
fun _tlsConnectTcp(host, port, timeout)
  var ip;
  try
    ip = _tlsGetHostByName(host);
  except
    raise 'tls: resolve: ' & @;
  end try;
  var h = _tlsState.socket(2, 1, 6);         // AF_INET, SOCK_STREAM, IPPROTO_TCP
  if h < 0 then raise 'tls: connect: socket failed'; end if;
  var fl = _tlsState.fcntl(h, _F_GETFL, 0);
  if fl >= 0 then _tlsState.fcntl(h, _F_SETFL, fl bit or _O_NONBLOCK); end if;
  var a = _tlsAddr16(ip, port);
  var rc = _tlsState.tcpConnect(h, a.toNum(-1), 16);
  if rc <> 0 then
    var en = _tlsErrnoValue();
    if en <> _EINPROGRESS then
      _tlsState.closeFd(h);
      raise 'tls: connect: ' & _tlsErrnoText(en);
    end if;
    var pfd = 0.toChar().x(8);
    int2str(h).move(pfd.toNum(-1));
    int2str(_POLLOUT).move(pfd.toNum(-1) + 4);
    var wait = -1;
    if timeout <> nil then wait = timeout; end if;
    var pr = _tlsState.poll(pfd.toNum(-1), 1, wait);
    if pr = 0 then
      _tlsState.closeFd(h);
      raise 'tls: connect: timeout';
    end if;
    if pr < 0 then
      var e2 = _tlsErrnoValue();
      _tlsState.closeFd(h);
      raise 'tls: connect: poll: ' & _tlsErrnoText(e2);
    end if;
    var soerr = 0.toChar().x(4);
    var slen = int2str(4);
    _tlsState.getsockopt(h, _SOL_SOCKET, _SO_ERROR, soerr.toNum(-1), slen.toNum(-1));
    var so = soerr.toByte(0) + soerr.toByte(1) * 256 + soerr.toByte(2) * 65536 + soerr.toByte(3) * 16777216;
    if so <> 0 then
      _tlsState.closeFd(h);
      raise 'tls: connect: ' & _tlsErrnoText(so);
    end if;
  end if;
  if fl >= 0 then _tlsState.fcntl(h, _F_SETFL, fl); end if;
  result = h;
end fun;

// TLS handshake on a connected socket; returns [ssl, ctx] or raises with the
// stage prefix. Verification: SSL_VERIFY_NONE during the handshake, the
// result is read afterwards so the error message can name the cause.
fun _tlsHandshake(fd, host, verify, timeout)
  var ctx = _tlsState.ctxNew(_tlsState.method());
  if ctx = 0 then raise 'tls: handshake: SSL_CTX_new failed'; end if;
  if verify then _tlsState.defPaths(ctx); end if;
  if not verify then _tlsState.setVerify(ctx, 0, 0); end if;
  var ssl = _tlsState.sslNew(ctx);
  if ssl = 0 then
    _tlsState.ctxFree(ctx);
    raise 'tls: handshake: SSL_new failed';
  end if;
  if _tlsState.setFd(ssl, fd) <> 1 then
    _tlsState.sslFree(ssl);
    _tlsState.ctxFree(ctx);
    raise 'tls: handshake: SSL_set_fd failed';
  end if;
  _tlsState.set1Host(ssl, host);
  // RFC 6066 forbids an IP literal in the SNI extension; send it only for
  // DNS names. Hostname verification above still applies to both.
  if not _tlsIsIP(host) then
    _tlsState.ctrl(ssl, _CTRL_SNI, 0, host.toNum(-1));
  end if;
  if timeout <> nil then _tlsSetTimeout(fd, timeout); end if;
  var rc = _tlsState.connect(ssl);
  if timeout <> nil then _tlsClearTimeout(fd); end if;
  if rc <> 1 then
    // a socket timeout during the handshake surfaces as WANT_READ/WRITE
    var e = _tlsState.getError(ssl, rc);
    var msg = '';
    if (e = 2 or e = 3) and timeout <> nil then msg = 'timeout';
    else msg = _tlsSslErrText(ssl, rc); end if;
    _tlsState.sslFree(ssl);
    _tlsState.ctxFree(ctx);
    raise 'tls: handshake: ' & msg;
  end if;
  if verify then
    var v = _tlsState.verify(ssl);
    if v <> 0 then
      _tlsState.sslFree(ssl);
      _tlsState.ctxFree(ctx);
      raise 'tls: certificate: ' & _tlsVerifyText(v);
    end if;
  end if;
  result = new [ssl: ssl, ctx: ctx];
end fun;

// opts: [host, verify, timeout]; host is required for wrap. Key presence is
// checked with @has: false = nil in Fun, so `<> nil` cannot detect an
// explicitly passed false.
fun _tlsOpts(opts, needHost)
  var o = new [host: '', verify: true, timeout: nil];
  if opts <> nil then
    if opts.@has('host') then o.host = opts.host; end if;
    if opts.@has('verify') then o.verify = opts.verify; end if;
    if opts.@has('timeout') then o.timeout = opts.timeout; end if;
  end if;
  if o.host.type() <> 8 then raise 'tls: opts.host must be a string'; end if;
  if needHost and o.host = '' then raise 'tls: opts.host is required'; end if;
  if o.verify.type() <> 11 then raise 'tls: opts.verify must be a boolean'; end if;
  if o.timeout <> nil and o.timeout.type() <> 3 then raise 'tls: opts.timeout must be an integer'; end if;
  result = o;
end fun;

class _TlsStream(ssl, ctx, fd)
  var ssl = ssl;
  var ctx = ctx;
  var fd = fd;
  var closed = false;

  fun read(n)
    if this.closed then raise 'tls: read: stream is closed'; end if;
    var t = n.type();
    if t = 0 then raise 'tls: read size required'; end if;
    if t <> 3 then raise 'tls: read size must be an integer'; end if;
    if n < 0 then raise 'tls: read size must be >= 0'; end if;
    if n = 0 then result = ''; return; end if;
    var buf = 0.toChar().x(n);
    var r = _tlsState.read(this.ssl, buf.toNum(-1), n);
    if r > 0 then result = buf.substr(0, r); return; end if;
    if r = 0 then result = ''; return; end if;
    var e = _tlsState.getError(this.ssl, r);
    if e = 6 then result = ''; return; end if;
    if e = 5 then
      var en = _tlsErrnoValue();
      if en = 0 then result = ''; return; end if;
      raise 'tls: read: ' & _tlsErrnoText(en);
    end if;
    raise 'tls: read: ' & _tlsSslErrText(this.ssl, r);
  end fun;

  fun write(s)
    if this.closed then raise 'tls: write: stream is closed'; end if;
    var t = s.type();
    if t <> 8 then raise 'tls: write data must be a string'; end if;
    if s = '' then result = 0; return; end if;
    var r = _tlsState.write(this.ssl, s.toNum(-1), s.length());
    if r = s.length() then result = r; return; end if;
    if r > 0 then raise 'tls: write: partial write ' & r & ' of ' & s.length(); end if;
    var e = _tlsState.getError(this.ssl, r);
    if e = 5 then
      var en = _tlsErrnoValue();
      if en <> 0 then raise 'tls: write: ' & _tlsErrnoText(en); end if;
    end if;
    raise 'tls: write: ' & _tlsSslErrText(this.ssl, r);
  end fun;

  fun close()
    if this.closed then result = true; return; end if;
    this.closed = true;
    _tlsState.shutdown(this.ssl);
    _tlsState.sslFree(this.ssl);
    _tlsState.ctxFree(this.ctx);
    _tlsState.closeFd(this.fd);
    result = true;
  end fun;
end class;

class _TlsApi()
  fun connect(host, port, opts)
    _tlsBind();
    var h = host.type();
    if h <> 8 then raise 'tls: host must be a string'; end if;
    var pt = port.type();
    if pt <> 3 then raise 'tls: port must be an integer'; end if;
    var o = _tlsOpts(opts, false);
    o.host = host;
    var fd = _tlsConnectTcp(host, port, o.timeout);
    var hs = _tlsHandshake(fd, host, o.verify, o.timeout);
    result = _TlsStream(hs['ssl'], hs['ctx'], fd);
  end fun;

  fun wrap(conn, opts)
    _tlsBind();
    var ct = conn.type();
    if ct <> 3 then raise 'tls: wrap expects a socket handle (integer)'; end if;
    var o = _tlsOpts(opts, true);
    // refuse to swallow plain-text bytes read before the upgrade
    var peek = 0.toChar().x(1);
    var pr = _tlsState.recv(conn, peek.toNum(-1), 1, 2 bit or _MSG_DONTWAIT);
    if pr > 0 then raise 'tls: wrap: connection has unread data'; end if;
    if pr = 0 then raise 'tls: wrap: connection closed by peer'; end if;
    var hs = _tlsHandshake(conn, o.host, o.verify, o.timeout);
    result = _TlsStream(hs['ssl'], hs['ctx'], conn);
  end fun;
end class;

var tls = _TlsApi();
