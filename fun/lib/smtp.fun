// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// smtp: an RFC 5321 client for sending mail. The protocol state machine and
// the MIME message builder live here in Fun (no OS ships an SMTP client
// library); transport encryption comes from the tls module, which uses the
// host system's TLS library.
//
//     use 'smtp.fun';
//     var s = smtp.open('smtp.example.com', 587,
//                       [user: 'a@t', pass: 'p', timeout: 10000]);
//     var msg = smtp.message([from: 'a@t', 'to': ['b@t'],
//                             subject: 'report', body: '...']);
//     s.send('a@t', ['b@t'], msg);       // envelope; Bcc goes here only
//     s.close();
//
// Ports: 465 = implicit TLS, 587/25 = plain then STARTTLS when the server
// advertises it (opts.tls: 'auto' default; 'implicit' and 'none' override).
// AUTH PLAIN/LOGIN is chosen from the server's EHLO advertisement. Every
// failure raises 'smtp: <stage>: <reply code> <text>'.
//
// The message builder separates envelope addresses from headers: Bcc
// recipients go into send()'s tos and never into the message. Non-ASCII
// subjects are RFC 2047 encoded words; non-ASCII bodies and attachments are
// base64; lines are always CRLF (bare LF is normalized).
//
// Unix/macOS only: the plain-text phase uses self-contained lazy socket FFI
// (the module loads in safe builds and on Windows, and raises on first use).

use 'tls.fun';
use 'lib-host.fun';
use 'lib-utils.fun';
use 'lib-base64.fun';
use 'uuid.fun';

var _CRLF = 13.toChar() & 10.toChar();
var _SMTP_CHUNK = 4096;

// platform socket constants (DyLib(lnx, mac)); see tls-unx for the precedent
var _SOL_SOCKET   = DyLib(1, 0xffff);
var _SO_ERROR     = DyLib(4, 0x1007);
var _SO_RCVTIMEO  = DyLib(20, 0x1006);
var _SO_SNDTIMEO  = DyLib(21, 0x1005);
var _O_NONBLOCK   = DyLib(0x800, 4);
var _F_GETFL = 3;
var _F_SETFL = 4;
var _EINPROGRESS  = DyLib(115, 36);
var _POLLOUT = 4;

var _smtpState = new [
  hostKnown: false,
  bound: false,
  isMac: false,
  isLinux: false,
  ptrBytes: 4,
  socket: nil,
  tcpConnect: nil,
  recv: nil,
  send: nil,
  fcntl: nil,
  poll: nil,
  setsockopt: nil,
  getsockopt: nil,
  closeFd: nil,
  strerror: nil,
  errnoFn: nil,
  memcpy: nil,
  gethostname: nil,
  timeFn: nil,
  strtoull: nil,
  freeaddrinfo: nil,
  signal: nil
];

fun _smtpHost()
  if _smtpState.hostKnown then result = true; return; end if;
  var host = 'host'.arg().getJson(fd: true);
  _smtpState.isMac = host.os = 'macos';
  _smtpState.isLinux = host.os = 'linux';
  _smtpState.ptrBytes = host.bits div 8;
  if not _smtpState.isMac and not _smtpState.isLinux then
    raise 'smtp: unsupported host ' & host.os;
  end if;
  _smtpState.hostKnown = true;
  result = true;
end fun;

fun _smtpErrnoValue()
  var errnoFn = _smtpState.errnoFn;
  var memcpy = _smtpState.memcpy;
  if errnoFn = nil or memcpy = nil then result = -1; return; end if;
  var p = errnoFn();
  if p = nil or p = 0 then result = -1; return; end if;
  var buf = 0.toChar().x(4);
  memcpy(buf.toNum(-1), p, 4);
  result = buf.toByte(0) + buf.toByte(1) * 256 + buf.toByte(2) * 65536 + buf.toByte(3) * 16777216;
end fun;

fun _smtpErrnoText(e)
  if e < 0 then result = ''; return; end if;
  var s = '';
  if _smtpState.strerror <> nil then s = _smtpState.strerror(e); end if;
  if s = nil or s = '' then result = 'errno ' & e;
  else result = s & ' (' & e & ')'; end if;
end fun;

fun _smtpBind()
  if _smtpState.bound then result = true; return; end if;
  try
    _smtpHost();
    var sys = LibC();
    _smtpState.socket      = sys.getapi('socket', 'iii:i');
    _smtpState.tcpConnect  = sys.getapi('connect', 'iii:i');
    _smtpState.recv        = sys.getapi('recv', 'ippi:i');
    _smtpState.send        = sys.getapi('send', 'ipii:i');
    _smtpState.fcntl       = sys.getapi('fcntl', 'iii:i', variadic: 2);
    _smtpState.poll        = sys.getapi('poll', 'pip:i');
    _smtpState.setsockopt  = sys.getapi('setsockopt', 'iiipi:i');
    _smtpState.getsockopt  = sys.getapi('getsockopt', 'iiipp:i');
    _smtpState.closeFd     = sys.getapi('close', 'i:i');
    _smtpState.gethostname = sys.getapi('gethostname', 'pi:i');
    _smtpState.timeFn      = sys.getapi('time', 'p:l');
    _smtpState.strtoull    = sys.getapi('strtoull', 'pii:l');
    _smtpState.freeaddrinfo = sys.getapi('freeaddrinfo', 'i:i');
    try
      _smtpState.strerror = sys.getapi('strerror', 'i:s');
    except
      _smtpState.strerror = nil;
    end try;
    if _smtpState.isMac then
      _smtpState.errnoFn = sys.getapi('__error', ':p');
      _smtpState.memcpy  = sys.getapi('memcpy', 'ppn:p');
    else
      _smtpState.errnoFn = sys.getapi('__errno_location', ':p');
      _smtpState.memcpy  = sys.getapi('memcpy', 'ppn:p');
    end if;
    // writes to a peer that closed must raise EPIPE in Fun, not kill the
    // interpreter with SIGPIPE (process.run ignores it around its pump too)
    _smtpState.signal = sys.getapi('signal', 'ii:i');
    _smtpState.signal(13, 1);
    _smtpState.bound = true;
    result = true;
  except
    raise 'smtp: SMTP is unavailable; ' & @;
  end try;
end fun;

// TCP connect with the optional timeout: non-blocking connect + poll
fun _smtpConnectTcp(host, port, timeout)
  var ip;
  try
    ip = _smtpGetHostByName(host);
  except
    raise 'smtp: connect: ' & @;
  end try;
  var h = _smtpState.socket(2, 1, 6);        // AF_INET, SOCK_STREAM, IPPROTO_TCP
  if h < 0 then raise 'smtp: connect: socket failed'; end if;
  var fl = _smtpState.fcntl(h, _F_GETFL, 0);
  if fl >= 0 then _smtpState.fcntl(h, _F_SETFL, fl bit or _O_NONBLOCK); end if;
  var a = _smtpAddr16(ip, port);
  var rc = _smtpState.tcpConnect(h, a.toNum(-1), 16);
  if rc <> 0 then
    var en = _smtpErrnoValue();
    if en <> _EINPROGRESS then
      _smtpState.closeFd(h);
      raise 'smtp: connect: ' & _smtpErrnoText(en);
    end if;
    var pfd = 0.toChar().x(8);
    int2str(h).move(pfd.toNum(-1));
    int2str(_POLLOUT).move(pfd.toNum(-1) + 4);
    var wait = -1;
    if timeout <> nil then wait = timeout; end if;
    var pr = _smtpState.poll(pfd.toNum(-1), 1, wait);
    if pr = 0 then
      _smtpState.closeFd(h);
      raise 'smtp: connect: timeout';
    end if;
    if pr < 0 then
      var e2 = _smtpErrnoValue();
      _smtpState.closeFd(h);
      raise 'smtp: connect: poll: ' & _smtpErrnoText(e2);
    end if;
    var soerr = 0.toChar().x(4);
    var slen = int2str(4);
    _smtpState.getsockopt(h, _SOL_SOCKET, _SO_ERROR, soerr.toNum(-1), slen.toNum(-1));
    var so = soerr.toByte(0) + soerr.toByte(1) * 256 + soerr.toByte(2) * 65536 + soerr.toByte(3) * 16777216;
    if so <> 0 then
      _smtpState.closeFd(h);
      raise 'smtp: connect: ' & _smtpErrnoText(so);
    end if;
  end if;
  if fl >= 0 then _smtpState.fcntl(h, _F_SETFL, fl); end if;
  result = h;
end fun;

// keep the per-command reply timeout on the session socket for its lifetime
fun _smtpSetTimeout(fd, timeout)
  if timeout = nil then return; end if;
  var tv = 0.toChar().x(_smtpState.ptrBytes * 2);
  int2str(timeout div 1000).move(tv.toNum(-1));
  int2str(timeout mod 1000 * 1000).move(tv.toNum(-1) + _smtpState.ptrBytes);
  _smtpState.setsockopt(fd, _SOL_SOCKET, _SO_RCVTIMEO, tv.toNum(-1), _smtpState.ptrBytes * 2);
  _smtpState.setsockopt(fd, _SOL_SOCKET, _SO_SNDTIMEO, tv.toNum(-1), _smtpState.ptrBytes * 2);
end fun;

// --- socket helpers shared with the plain-text phase (tls-unx recipes) -----

fun _smtpReadU64(s, off)
  var h = str2hex(s.substr(off, 8));
  var big = h.substr(14,2) & h.substr(12,2) & h.substr(10,2) & h.substr(8,2)
          & h.substr(6,2) & h.substr(4,2) & h.substr(2,2) & h.substr(0,2);
  var tb = ' '.x(20);
  ('0x' & big).move(tb.toNum(-1));
  result = _smtpState.strtoull(tb.toNum(-1), 0, 16);
end fun;

fun _smtpAddr2IP(addr)
  result = int2ip(str2int(addr.substr(4, 4)));
end fun;

fun _smtpGetHostByName(name)
  if name =~ %^\d+\.\d+\.\d+\.\d+$% then
    result = name;
    return;
  end if;
  var hints = 0.toChar().x(48);
  int2str(2).move(hints.toNum(-1) + 4);      // AF_INET
  int2str(1).move(hints.toNum(-1) + 8);      // SOCK_STREAM
  var res = 0.toChar().x(8);
  var rc = _smtpState.getaddrinfo(name.toNum(-1), 0, hints.toNum(-1), res.toNum(-1));
  if rc <> 0 then
    raise 'cannot resolve host ' & name;
  end if;
  var p  = _smtpReadU64(res, 0);
  var ai = 0.toChar().x(48);
  _smtpState.memcpy(ai.toNum(-1), p, 48);
  var sa = _smtpReadU64(ai, DyLib(24, 32));  // ai_addr: 24 glibc, 32 Darwin
  var sb = 0.toChar().x(16);
  _smtpState.memcpy(sb.toNum(-1), sa, 16);
  _smtpState.freeaddrinfo(p);
  result = _smtpAddr2IP(sb);
end fun;

fun _smtpAddr16(ip, port)
  port = port div 1;
  port = port >> 8 + port mod 256 << 8;
  ip = int2str(ip2int(ip));
  if _smtpState.isMac then
    result = int2str(16 + (2 << 8) + (port << 16)) & ip & 0.toChar().x(8);
  else
    result = int2str(2 + (port << 16)) & ip & 0.toChar().x(8);
  end if;
end fun;

// --- SMTP dialogue ----------------------------------------------------------

// read one CRLF line from the session buffer, refilling from the socket or
// the tls stream; transport errors carry the tls/errno text
fun _sessReadLine(sess)
  loop
    var p = sess.buf.subpos(_CRLF);
    if p >= 0 then
      result = sess.buf.substr(0, p);
      sess.buf = sess.buf.substr(p + 2);
      return;
    end if;
    var chunk = '';
    if sess.tls <> nil then
      chunk = sess.tls.read(_SMTP_CHUNK);
    else
      var b = 0.toChar().x(_SMTP_CHUNK);
      var r = _smtpState.recv(sess.fd, b.toNum(-1), _SMTP_CHUNK, 0);
      if r > 0 then chunk = b.substr(0, r); end if;
      if r <= 0 then
        var en = _smtpErrnoValue();
        if r = 0 then raise 'connection closed by peer'; end if;
        if en = 11 or en = 35 then raise 'timeout'; end if;   // EAGAIN / EWOULDBLOCK
        raise _smtpErrnoText(en);
      end if;
    end if;
    if chunk = '' then raise 'connection closed by peer'; end if;
    sess.buf = sess.buf & chunk;
  end loop;
end fun;

// one reply: multi-line aware ('250-' continuation, '250 ' final);
// returns [code, text, lines]; transport errors are wrapped with the stage
fun _sessReply(sess)
  var code = 0;
  var text = '';
  var lines = new [];
  var first = true;
  loop
    var line = '';
    try
      line = _sessReadLine(sess);
    except
      var e = '' & @;
      if e =~ %want\x20read% or e =~ %timeout% then
        raise 'smtp: ' & sess.stage & ': timeout';
      end if;
      raise 'smtp: ' & sess.stage & ': ' & e;
    end try;
    if line.length() < 3 then
      raise 'smtp: ' & sess.stage & ': malformed reply ' & line;
    end if;
    var c = line.substr(0, 3).toNum(0);
    var rest = line.substr(3);
    var sep = rest.substr(0, 1);
    if sep = '-' or sep = ' ' then rest = rest.substr(1); end if;
    lines.@add(rest);
    if first then text = rest; elsif rest <> '' then text = text & ' ' & rest; end if;
    first = false;
    code = c;
    if sep <> '-' then exit; end if;
  end loop;
  result = new [code: code, text: text, lines: lines];
end fun;

fun _sessSendLine(sess, line)
  if sess.closed then raise 'smtp: ' & sess.stage & ': session is closed'; end if;
  var data = line & _CRLF;
  if sess.tls <> nil then
    sess.tls.write(data);
  else
    var off = 0;
    loop
      var r = _smtpState.send(sess.fd, data.substr(off).toNum(-1), data.length() - off, 0);
      if r < 0 then
        var en = _smtpErrnoValue();
        raise 'smtp: ' & sess.stage & ': ' & _smtpErrnoText(en);
      end if;
      off += r;
      if off >= data.length() then exit; end if;
    end loop;
  end if;
end fun;

fun _sessCmd(sess, line)
  _sessSendLine(sess, line);
  result = _sessReply(sess);
end fun;

fun _sessEhlo(sess)
  sess.stage = 'ehlo';
  var r = _sessCmd(sess, 'EHLO ' & sess.heloId);
  if r['code'] <> 250 then
    raise 'smtp: ehlo: ' & r['code'] & ' ' & r['text'];
  end if;
  // first line is the server greeting name; the rest are capabilities
  sess.caps = new [];
  var n = r['lines'].@count();
  for i = 1 to n - 1 do
    var cap = r['lines'][i];
    var sp = cap.subpos(' ');
    if sp > 0 then
      sess.caps[cap.substr(0, sp)] = cap.substr(sp + 1);
    else
      sess.caps[cap] = '';
    end if;
  end do;
  result = true;
end fun;

fun _sessStartTls(sess)
  sess.stage = 'starttls';
  var r = _sessCmd(sess, 'STARTTLS');
  if r['code'] <> 220 then
    raise 'smtp: starttls: ' & r['code'] & ' ' & r['text'];
  end if;
  sess.tls = tls.wrap(sess.fd, [host: sess.host, timeout: sess.timeout]);
  _sessEhlo(sess);          // capabilities reset after the upgrade
  result = true;
end fun;

fun _sessAuth(sess, user, pass)
  sess.stage = 'auth';
  if not sess.caps.@has('auth') then
    raise 'smtp: auth: server does not advertise AUTH';
  end if;
  var mechs = sess.caps['auth'];
  var r;
  if mechs =~ %PLAIN% then
    var token = Str2Base64(0.toChar() & user & 0.toChar() & pass);
    r = _sessCmd(sess, 'AUTH PLAIN ' & token);
  elsif mechs =~ %LOGIN% then
    r = _sessCmd(sess, 'AUTH LOGIN');
    if r['code'] <> 334 then
      raise 'smtp: auth: ' & r['code'] & ' ' & r['text'];
    end if;
    r = _sessCmd(sess, Str2Base64(user));
    if r['code'] <> 334 then
      raise 'smtp: auth: ' & r['code'] & ' ' & r['text'];
    end if;
    r = _sessCmd(sess, Str2Base64(pass));
  else
    raise 'smtp: auth: server does not advertise a supported mechanism';
  end if;
  if r['code'] <> 235 then
    raise 'smtp: auth: ' & r['code'] & ' ' & r['text'];
  end if;
  sess.authed = true;
  result = true;
end fun;

fun _sessSend(sess, from, tos, msg)
  if sess.closed then raise 'smtp: send: session is closed'; end if;
  var m = _smtpToCrlf(msg);
  sess.stage = 'mail';
  var r = _sessCmd(sess, 'MAIL FROM:<' & from & '>');
  if r['code'] <> 250 then
    raise 'smtp: mail: ' & r['code'] & ' ' & r['text'];
  end if;
  sess.stage = 'rcpt';
  var n = tos.@count();
  for i = 0 to n - 1 do
    var rr = _sessCmd(sess, 'RCPT TO:<' & tos[i] & '>');
    if rr['code'] <> 250 then
      raise 'smtp: rcpt: ' & tos[i] & ': ' & rr['code'] & ' ' & rr['text'];
    end if;
  end do;
  sess.stage = 'data';
  var dr = _sessCmd(sess, 'DATA');
  if dr['code'] <> 354 then
    raise 'smtp: data: ' & dr['code'] & ' ' & dr['text'];
  end if;
  _sessSendLine(sess, _smtpDotStuff(m));
  _sessSendLine(sess, '.');
  var fr = _sessReply(sess);
  if fr['code'] <> 250 then
    raise 'smtp: data: ' & fr['code'] & ' ' & fr['text'];
  end if;
  result = true;
end fun;

// split into lines: LF and CRLF both terminate a line (no trailing empty
// line for a final terminator); O(n) byte scan + one substr per line
fun _smtpSplitLines(s)
  var lines = new [];
  var start = 0;
  var i = 0;
  var n = s.length();
  while i < n do
    if s.toByte(i) = 10 then
      var endi = i;
      if endi > start and s.toByte(i - 1) = 13 then endi = i - 1; end if;
      lines.@add(s.substr(start, endi - start));
      start = i + 1;
    end if;
    i += 1;
  end do;
  if start < n then lines.@add(s.substr(start)); end if;
  result = lines;
end fun;

// join lines with CRLF: interleaved @add + @toJson(-1) (the csv round's fast
// concatenation; plain & would be quadratic)
fun _smtpJoinCrlf(lines)
  var parts = new [];
  var n = lines.@count();
  for i = 0 to n - 1 do
    parts.@add(lines[i]);
    parts.@add(_CRLF);
  end do;
  result = parts.@toJson(-1);
end fun;

// lines starting with '.' get a second dot; the message must already be CRLF
fun _smtpDotStuff(m)
  var lines = _smtpSplitLines(m);
  var n = lines.@count();
  for i = 0 to n - 1 do
    if lines[i].substr(0, 1) = '.' then lines[i] = '.' & lines[i]; end if;
  end do;
  result = _smtpJoinCrlf(lines);
end fun;

// bare LF (and lone CR) -> CRLF
fun _smtpToCrlf(s)
  result = _smtpJoinCrlf(_smtpSplitLines(s));
end fun;

class _SmtpSession(host, port, timeout)
  var fd = -1;
  var tls = nil;
  var host = host;
  var port = port;
  var timeout = timeout;
  var heloId = '[127.0.0.1]';
  var buf = '';
  var caps = new [];
  var stage = 'connect';
  var authed = false;
  var closed = false;

  fun capabilities()
    result = this.caps;
  end fun;

  fun send(from, tos, msg)
    _sessSend(this, from, tos, msg);
    result = true;
  end fun;

  fun close()
    if this.closed then result = true; return; end if;
    this.closed = true;
    try
      this.stage = 'quit';
      _sessCmd(this, 'QUIT');
    except
      // the peer may already be gone; the close below still runs
    end try;
    if this.tls <> nil then
      this.tls.close();
    else
      if this.fd >= 0 then _smtpState.closeFd(this.fd); end if;
    end if;
    result = true;
  end fun;
end class;

// --- message builder --------------------------------------------------------

// any byte above 127 (or a control char that needs encoding) -> base64 body
fun _smtpNeedsB64(s)
  var n = s.length();
  var i = 0;
  while i < n do
    var b = s.toByte(i);
    if b > 127 or (b < 9 and b <> 0) or b = 11 or b = 12 then result = true; return; end if;
    i += 1;
  end do;
  result = false;
end fun;

fun _smtpRfc2047(s)
  result = '=?utf-8?B?' & Str2Base64(s) & '?=';
end fun;

fun _smtpSubjectHeader(subject)
  var i = 0;
  var n = subject.length();
  while i < n do
    if subject.toByte(i) > 127 then result = _smtpRfc2047(subject); return; end if;
    i += 1;
  end do;
  result = subject;
end fun;

// RFC 5322 date from the epoch, in UTC (+0000): Thu, 01 Jan 1970 00:00:00 +0000
fun _smtpDate()
  var t = _smtpState.timeFn(0);
  var days = t div 86400;
  var secs = t mod 86400;
  var wd = (days + 4) mod 7;                 // 1970-01-01 was a Thursday
  var wdNames = 'Sun,Mon,Tue,Wed,Thu,Fri,Sat';
  var wdName = wdNames.substr(wd * 4, 3);
  var z = days + 719468;
  var era = z div 146097;
  if z < 0 then era = (z - 146096) div 146097; end if;
  var doe = z - era * 146097;
  var yoe = (doe - doe div 1460 + doe div 36524 - doe div 146096) div 365;
  var y = yoe + era * 400;
  var doy = doe - (365 * yoe + yoe div 4 - yoe div 100);
  var mp = (5 * doy + 2) div 153;
  var d = doy - (153 * mp + 2) div 5 + 1;
  var m = mp + 3;
  if m > 12 then m = m - 9; y += 1; end if;
  var monNames = 'JanFebMarAprMayJunJulAugSepOctNovDec';
  var monName = monNames.substr((m - 1) * 3, 3);
  var hh = secs div 3600;
  var mi = (secs div 60) mod 60;
  var ss = secs mod 60;
  result = wdName & ', ' & _smtpPad2(d) & ' ' & monName & ' ' & y & ' ' &
           _smtpPad2(hh) & ':' & _smtpPad2(mi) & ':' & _smtpPad2(ss) & ' +0000';
end fun;

fun _smtpPad2(v)
  if v < 10 then result = '0' & v; else result = '' & v; end if;
end fun;

// base64 for potentially large payloads: 3060-byte chunks (divisible by 3, so
// only the final chunk carries padding) joined via @toJson(-1)
fun _smtpB64(data)
  var parts = new [];
  var n = data.length();
  var i = 0;
  while i < n do
    parts.@add(toBase64(data.substr(i, 3060), 1));
    i += 3060;
  end do;
  result = parts.@toJson(-1);
end fun;

fun _smtpJoinAddrs(addrs)
  var out = '';
  var n = addrs.@count();
  for i = 0 to n - 1 do
    if i > 0 then out = out & ', '; end if;
    out = out & addrs[i];
  end do;
  result = out;
end fun;

fun _smtpHostname()
  var buf = 0.toChar().x(256);
  var rc = _smtpState.gethostname(buf.toNum(-1), 256);
  if rc <> 0 then result = '[127.0.0.1]'; return; end if;
  var name = buf.strlen();
  if name = '' then result = '[127.0.0.1]'; return; end if;
  result = name;
end fun;

fun _smtpMessageId(from)
  var at = from.subpos('@');
  var domain = 'localhost';
  if at >= 0 then domain = from.substr(at + 1); end if;
  result = '<' & UUID() & '@' & domain & '>';
end fun;

// normalize the address list: a string becomes a one-element list
fun _smtpAddrList(v)
  if v = nil then result = new []; return; end if;
  if v.type() = 8 then
    var l = new [];
    l.@add(v);
    result = l;
    return;
  end if;
  result = v;
end fun;

fun _smtpMessage(opts)
  _smtpBind();               // Date needs the clock; no server is contacted
  var from = '';
  var subject = '';
  var body = '';
  var toList = _smtpAddrList(opts['to']);
  var cc = _smtpAddrList(opts.cc);
  var atts = new [];
  if opts.from <> nil then from = opts.from; end if;
  if opts.subject <> nil then subject = opts.subject; end if;
  if opts.body <> nil then body = opts.body; end if;
  if opts.attachments <> nil then atts = opts.attachments; end if;
  if from = '' then raise 'smtp: message: from is required'; end if;
  if toList.@count() = 0 then raise 'smtp: message: to is required'; end if;

  var head = '';
  head = head & 'From: ' & from & _CRLF;
  head = head & 'To: ' & _smtpJoinAddrs(toList) & _CRLF;
  if cc.@count() > 0 then head = head & 'Cc: ' & _smtpJoinAddrs(cc) & _CRLF; end if;
  head = head & 'Subject: ' & _smtpSubjectHeader(subject) & _CRLF;
  head = head & 'Date: ' & _smtpDate() & _CRLF;
  head = head & 'Message-ID: ' & _smtpMessageId(from) & _CRLF;
  head = head & 'MIME-Version: 1.0' & _CRLF;

  var bodyText = _smtpToCrlf(body);
  var attCount = atts.@count();

  if attCount = 0 then
    if _smtpNeedsB64(bodyText) then
      head = head & 'Content-Type: text/plain; charset=utf-8' & _CRLF;
      head = head & 'Content-Transfer-Encoding: base64' & _CRLF;
      return head & _CRLF & _smtpB64(bodyText);
    end if;
    head = head & 'Content-Type: text/plain; charset=utf-8' & _CRLF;
    head = head & 'Content-Transfer-Encoding: 7bit' & _CRLF;
    return head & _CRLF & bodyText;
  end if;

  var boundary = 'fun-' & UUID();
  head = head & 'Content-Type: multipart/mixed; boundary="' & boundary & '"' & _CRLF;
  var out = head & _CRLF;
  out = out & '--' & boundary & _CRLF;
  out = out & 'Content-Type: text/plain; charset=utf-8' & _CRLF;
  if _smtpNeedsB64(bodyText) then
    out = out & 'Content-Transfer-Encoding: base64' & _CRLF & _CRLF;
    out = out & _smtpB64(bodyText) & _CRLF;
  else
    out = out & 'Content-Transfer-Encoding: 7bit' & _CRLF & _CRLF;
    out = out & bodyText & _CRLF;
  end if;
  var n = 0;
  for i = 0 to attCount - 1 do
    var name = atts[i]['name'];
    var data = atts[i]['data'];
    n += 1;
    out = out & '--' & boundary & _CRLF;
    out = out & 'Content-Type: application/octet-stream; name="' & name & '"' & _CRLF;
    out = out & 'Content-Transfer-Encoding: base64' & _CRLF;
    out = out & 'Content-Disposition: attachment; filename="' & name & '"' & _CRLF & _CRLF;
    out = out & _smtpB64(data) & _CRLF;
  end do;
  out = out & '--' & boundary & '--' & _CRLF;
  result = out;
end fun;

// --- public API --------------------------------------------------------------

fun _smtpOpts(opts)
  var o = new [user: '', pass: '', timeout: nil, tls: 'auto'];
  if opts <> nil then
    if opts.@has('user') then o.user = opts.user; end if;
    if opts.@has('pass') then o.pass = opts.pass; end if;
    if opts.@has('timeout') then o.timeout = opts.timeout; end if;
    if opts.@has('tls') then o.tls = opts.tls; end if;
  end if;
  if o.user.type() <> 8 then raise 'smtp: opts.user must be a string'; end if;
  if o.pass.type() <> 8 then raise 'smtp: opts.pass must be a string'; end if;
  if o.timeout <> nil and o.timeout.type() <> 3 then raise 'smtp: opts.timeout must be an integer'; end if;
  if o.tls <> 'auto' and o.tls <> 'implicit' and o.tls <> 'none' then
    raise 'smtp: opts.tls must be auto, implicit or none';
  end if;
  result = o;
end fun;

class _SmtpApi()
  fun open(host, port, opts)
    _smtpBind();
    if host.type() <> 8 then raise 'smtp: host must be a string'; end if;
    if port.type() <> 3 then raise 'smtp: port must be an integer'; end if;
    var o = _smtpOpts(opts);
    var fd = _smtpConnectTcp(host, port, o.timeout);
    var sess = _SmtpSession(host, port, o.timeout);
    sess.fd = fd;
    if o.tls = 'implicit' or (port = 465 and o.tls <> 'none') then
      sess.stage = 'connect';
      try
        sess.tls = tls.wrap(fd, [host: host, timeout: o.timeout]);
      except
        raise 'smtp: connect: ' & @;
      end try;
    end if;
    _smtpSetTimeout(fd, o.timeout);
    sess.stage = 'greet';
    var g = _sessReply(sess);
    if g['code'] <> 220 then
      raise 'smtp: greet: ' & g['code'] & ' ' & g['text'];
    end if;
    _sessEhlo(sess);
    if o.tls = 'auto' and sess.tls = nil and sess.caps.@has('starttls') then
      _sessStartTls(sess);
    end if;
    if o.user <> '' then _sessAuth(sess, o.user, o.pass); end if;
    result = sess;
  end fun;

  fun message(opts)
    result = _smtpMessage(opts);
  end fun;
end class;

var smtp = _SmtpApi();
