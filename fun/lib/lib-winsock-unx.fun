// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-winsock-unx: the Unix (Linux/macOS) backend of lib-winsock -- BSD sockets.
//
// Scope: the SOCKET LAYER, hostname resolution and the SYNCHRONOUS servers
// (UDP and HTTP/WebSocket). Everything here runs on the CALLING thread with a
// plain poll(2) event loop and invokes its callbacks inline; there are no
// worker threads. See art/notes/linux-threading.md for why (Fun's per-function
// variable stack is not re-entrant across threads).
//
// Simple async: Server.UDP / Server.HTTP expose Post/After/Every, serviced by
// the same poll loop between socket events (Scheduler in lib-winsock-base.fun).
// Repeating work and "defer this until the next loop turn" therefore need no
// threads. Going further (blocking work off the evaluation thread) still needs
// the threading decision in linux-threading.md.
//
// Why it is not a drop-in translation of lib-winsock.fun:
//   * The Windows class is bound to `WSAAsyncSelect(socket, hwnd, msg, event)`
//     plus a user32 message pump: datagrams/reads arrive as window messages and
//     OnMessage() dispatches them. There is no hwnd/message pump on Unix.
//   * The replacement is a poll(2) loop. For UDP it is Run/RunOnce; for HTTP it
//     is Run/RunOnce too (accept + per-client reads), with onGet() called inline.
//
//     var srv = Server.UDP('0.0.0.0', 9999, (data, ip, port){ ... });
//     $if srv.Start() then
//       srv.RunOnce(500);        // one poll+recv, for scripts that drive their own loop
//       // or: srv.Run(nil);    // block forever dispatching datagrams
//     end if;
//
//     var web = Server.HTTP('0.0.0.0', 8080, (req, header, body, sock){ ... });
//     web.Start();
//     web.Run(nil);              // handler calls web.Reply200(body, sock)
//
// Byte order / struct layout: BSD `sockaddr_in` is 16 bytes on both hosts, and
// the port/address fields sit at the same offsets (2 and 4). Only the family
// word differs: Linux `sa_family` is a 16-bit field at offset 0, Darwin leads
// with an 8-bit `sin_len` then an 8-bit `sin_family`, so Addr16 branches. The
// sockaddr the kernel returns is read with Addr2IP, which ignores the family
// bytes and therefore needs no branch.
//
// HTTP/WebSocket protocol + connection bookkeeping live in lib-winsock-base.fun
// (class HttpBase, shared with lib-winsock.fun); this file implements the
// HttpBase hooks (SendOnce/Read/CloseSock/ShutdownSock/Delay/Fatal), the
// poll(2) pump and the socket layer. `class HttpServerBase = HttpBase()` is top level
// because Fun cannot inherit a nested class from a top-level one; it is
// re-exposed as `Server.HTP` / `Server.HTTP` by assignment below.
//
// FFI notes (from lib-ajax-lnx / library-port-plan.md):
//   * native handles live in plain module-level variables, never in a set member;
//   * OUT parameters are passed as the REAL string address, `buf.toNum(-1)`, not
//     as 's' (which would hand libc a throw-away copy and lose the write);
//   * on input, 'i'/'l'/'n' all land in the same 8-byte GPR slot, so a raw
//     64-bit address survives regardless of the declared char.

use 'lib-utils.fun';
use 'lib-winsock-base.fun';
use 'lib-host.fun';

//--------------------------------------------------------------
// constants
//
// Most BSD numbers match between Linux and Darwin (AF_INET, SOCK_*, IPPROTO_*,
// POLL*, SD_SEND), but the socket/option names below do not -- Darwin uses
// SOL_SOCKET=0xffff and its own SO_*/IP_* values. Values are the stable ABI
// numbers from <sys/socket.h> on each host.
//--------------------------------------------------------------
var AF_INET       = 2;
var SOCK_STREAM   = 1;
var SOCK_DGRAM    = 2;
var IPPROTO_IP    = 0;
var IPPROTO_TCP   = 6;
var IPPROTO_UDP   = 17;
var SOL_SOCKET    = DyLib(1, 0xffff);
var SO_REUSEADDR  = DyLib(2, 0x0004);
var SO_BROADCAST  = DyLib(6, 0x0020);
var IP_ADD_MEMBERSHIP = DyLib(35, 12);
var POLLIN        = 1;
var POLLERR       = 8;
var POLLHUP       = 16;
var POLLNVAL      = 32;
var SD_SEND       = 1;
var BUFFERSIZE    = 65536;   // one full UDP datagram
var BackLog       = 128;  // 5 overflowed the accept queue: single-threaded accept loop + client 1s/3s SYN retries

//--------------------------------------------------------------
// libc handles (plain module-level vars)
//--------------------------------------------------------------
var _socket   = LibC().getapi('socket',   'iii:i');
var _bind     = LibC().getapi('bind',     'iii:i');
var _connect  = LibC().getapi('connect',  'iii:i');
var _listen   = LibC().getapi('listen',   'ii:i');
var _accept   = LibC().getapi('accept',   'iii:i');
var _send     = LibC().getapi('send',     'iiii:l');
var _recv     = LibC().getapi('recv',     'iiii:l');
var _sendto   = LibC().getapi('sendto',   'iiiiii:l');
var _recvfrom = LibC().getapi('recvfrom', 'iiiiii:l');
var _setsockopt = LibC().getapi('setsockopt', 'iiiiii:i');
var _getsockname = LibC().getapi('getsockname', 'iiii:i');
var _getpeername = LibC().getapi('getpeername', 'iiii:i');
var _shutdown = LibC().getapi('shutdown', 'ii:i');
var _close    = LibC().getapi('close',    'i:i');
var _poll     = LibC().getapi('poll',     'iii:i');
var _memcpy   = LibC().getapi('memcpy',   'ppn:p');
// errno accessor: glibc has __errno_location(), Darwin has __error().
var _errno_loc = LibC().getapi(DyLib('__errno_location', '__error'), ':p');
var _strerror = LibC().getapi('strerror', 'i:s');
var _usleep   = LibC().getapi('usleep',   'i:i');
var _getaddrinfo  = LibC().getapi('getaddrinfo',  'iiii:i');
var _freeaddrinfo = LibC().getapi('freeaddrinfo', 'i:i');
var _gai_strerror = LibC().getapi('gai_strerror', 'i:s');

//--------------------------------------------------------------
// errors
//--------------------------------------------------------------
fun Errno()
  var b = 0.toChar().x(4);
  _memcpy(b.toNum(-1), _errno_loc(), 4);
  result = str2int(b);
end fun;

fun ErrMsg()
  var e = Errno();
  result = _strerror(e) & ' (' & e & ')';
end fun;

// read one pointer-width (8-byte) little-endian value at byte offset off.
// str2int only reads 4 bytes, so assemble the high half explicitly.
fun ReadU64(s, off)
  var t = s.substr(off, 8);
  result = t.toNum(ptr: 1) + t.substr(4).toNum(ptr: 1) * 4294967296;
end fun;

//--------------------------------------------------------------
// hostname resolution (getaddrinfo; hostent's LP64 layout differs from WinSock)
//--------------------------------------------------------------
fun getHostByName(name)
  // numeric addresses need no lookup
  if name =~ %^\d+\.\d+\.\d+\.\d+$% then
    result = name;
    return;
  end if;
  // struct addrinfo is 48 bytes on x86_64; only ai_family/ai_socktype matter.
  var hints = 0.toChar().x(48);
  int2str(AF_INET)     .move(hints.toNum(-1) + 4);
  int2str(SOCK_STREAM) .move(hints.toNum(-1) + 8);
  var res = 0.toChar().x(8);
  var rc = _getaddrinfo(name.toNum(-1), 0, hints.toNum(-1), res.toNum(-1));
  if rc <> 0 then
    raise 'lib-winsock-unx: cannot resolve host ' & name & ': ' & _gai_strerror(rc);
  end if;
  var p  = ReadU64(res, 0);              // struct addrinfo *
  var ai = 0.toChar().x(48);
  _memcpy(ai.toNum(-1), p, 48);
  // ai_addr offset: 24 on glibc (ai_addr before ai_canonname), 32 on Darwin
  // (ai_canonname before ai_addr). struct addrinfo is 48 bytes on both.
  var sa = ReadU64(ai, DyLib(24, 32));    // ai_addr (struct sockaddr *)
  var sb = 0.toChar().x(16);
  _memcpy(sb.toNum(-1), sa, 16);
  var port;
  result = Addr2IP(sb, var port);        // numeric ip, port ignored
  _freeaddrinfo(p);
end fun;

//--------------------------------------------------------------
// socket primitives
//--------------------------------------------------------------
fun TCPSocket()
  result = _socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
end fun;

fun UDPSocket()
  result = _socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
end fun;

// 16-byte sockaddr_in; same port/address bytes on both hosts, but the family
// word differs (see the header note).
fun Addr16(ip, port)
  port = port div 1;
  port = port >> 8 + port mod 256 << 8;
  if ip =~ /[a-z]/i then
    ip = getHostByName(ip);
  end if;
  ip = int2str(ip2int(ip));
  if IsMac() then
    // Darwin: sin_len=16, sin_family=AF_INET (offset 1), then port big-endian
    result = int2str(16 + (AF_INET << 8) + (port << 16)) & ip & 0.toChar().x(8);
  else
    result = int2str(AF_INET + (port << 16)) & ip & 0.toChar().x(8);
  end if;
end fun;

// one int32 as a little-endian 4-byte buffer (for setsockopt optval / socklen)
fun IntBuf(v)
  result = int2str(v);
end fun;

fun ListenSocket(ip, port, backlog)
  var h = TCPSocket();
  if h < 0 then
    raise 'lib-winsock-unx: socket: ' & ErrMsg();
  end if;
  _setsockopt(h, SOL_SOCKET, SO_REUSEADDR, IntBuf(1).toNum(-1), 4);
  var a = Addr16(ip, port);
  if _bind(h, a.toNum(-1), 16) <> 0 then
    var e = ErrMsg();
    _close(h);
    raise 'lib-winsock-unx: bind ' & ip & ':' & port & ': ' & e;
  end if;
  if backlog = nil then
    backlog = BackLog;
  end if;
  if _listen(h, backlog) <> 0 then
    var e2 = ErrMsg();
    _close(h);
    raise 'lib-winsock-unx: listen ' & ip & ':' & port & ': ' & e2;
  end if;
  result = h;
end fun;

// blocking connect: returns the connected handle or raises
fun ConnectSocket(ip, port)
  var h = TCPSocket();
  if h < 0 then
    raise 'lib-winsock-unx: socket: ' & ErrMsg();
  end if;
  var a = Addr16(ip, port);
  if _connect(h, a.toNum(-1), 16) <> 0 then
    var e = ErrMsg();
    _close(h);
    raise 'lib-winsock-unx: connect ' & ip & ':' & port & ': ' & e;
  end if;
  result = h;
end fun;

// accept one connection; returns the handle or nil when none is pending
fun AcceptSocket(h)
  var sa  = 0.toChar().x(16);
  var sal = IntBuf(16);
  var s = _accept(h, sa.toNum(-1), sal.toNum(-1));
  if s < 0 then
    result = nil;
  else
    result = s;
  end if;
end fun;

// send the whole string, blocking until done; returns bytes sent
fun SendAll(h, s)
  var i = 0;
  while i < s.length() loop
    var l = _send(h, s.substr(i).toNum(-1), s.length() - i, 0);
    if l > 0 then
      i += l;
    else
      raise 'lib-winsock-unx: send: ' & ErrMsg();
    end if;
  end loop;
  result = i;
end fun;

// up to `size` bytes; nil on orderly EOF (peer closed)
fun RecvSome(h, size)
  var b = 0.toChar().x(size);
  var i = _recv(h, b.toNum(-1), size, 0);
  if i < 0 then
    raise 'lib-winsock-unx: recv: ' & ErrMsg();
  elsif i = 0 then
    result = nil;
  else
    result = b.substr(0, i);
  end if;
end fun;

// read until the peer closes; nil if nothing arrived before EOF
fun RecvAll(h)
  var out = nil;
  loop
    var b = RecvSome(h, BUFFERSIZE);
    exit when b = nil;
    out = out or '';
    out &= b;
  end loop;
  result = out;
end fun;

fun Shutdown(h, how)
  if how = nil then how = SD_SEND; end if;
  result = _shutdown(h, how);
end fun;

fun CloseSocket(h)
  result = _close(h);
end fun;

// local ip/port a socket is bound to: [ip, port]. Useful after binding port 0.
fun LocalAddr(h)
  var uc  = 0.toChar().x(16);
  var ucl = IntBuf(16);
  if _getsockname(h, uc.toNum(-1), ucl.toNum(-1)) <> 0 then
    result = nil;
    return;
  end if;
  var port;
  var pip = Addr2IP(uc, var port);
  result = new [ip: pip, port: port];
end fun;

// remote ip/port of a connected socket: [ip, port]
fun PeerAddr(h)
  var uc  = 0.toChar().x(16);
  var ucl = IntBuf(16);
  if _getpeername(h, uc.toNum(-1), ucl.toNum(-1)) <> 0 then
    result = nil;
    return;
  end if;
  var port;
  var pip = Addr2IP(uc, var port);
  result = new [ip: pip, port: port];
end fun;

// client-style helpers on a bare UDPSocket()/TCPSocket() handle
fun SendTo(h, ip, port, data)
  var a = Addr16(ip, port);
  result = _sendto(h, data.toNum(-1), data.length(), 0, a.toNum(-1), 16);
end fun;

// block up to `timeout` ms (nil = forever) for one datagram; returns
// [data, ip, port, size] or nil on timeout.
fun RecvFrom(h, timeout)
  var t = -1;
  if timeout <> nil then t = timeout; end if;
  var pfd = int2str(h) & int2str(POLLIN).substr(0, 2) & int2str(0).substr(0, 2);
  if _poll(pfd.toNum(-1), 1, t) <= 0 then
    result = nil;
    return;
  end if;
  var b   = 0.toChar().x(BUFFERSIZE);
  var uc  = 0.toChar().x(16);
  var ucl = IntBuf(16);
  var i = _recvfrom(h, b.toNum(-1), BUFFERSIZE, 0, uc.toNum(-1), ucl.toNum(-1));
  if i <= 0 then
    result = nil;
    return;
  end if;
  var port;
  var pip = Addr2IP(uc, var port);
  result = new [data: b.substr(0, i), ip: pip, port: port, size: i];
end fun;

//--------------------------------------------------------------
// UDP server (poll(2) on the calling thread)
//--------------------------------------------------------------
class UDP(ip, port, onGet, broadCast) # onGet(data, ip, port)
  var handle  = 0;
  var running = false;
  var sched   = Scheduler();

  //---- simple async (timers/tasks serviced by Run/RunOnce) ------
  fun Post(fx)          result = this.sched.Post(fx);          end fun;
  fun After(ms, fx)     result = this.sched.After(ms, fx);     end fun;
  fun Every(ms, fx)     result = this.sched.Every(ms, fx);     end fun;

  fun Start()
    handle = UDPSocket();
    if handle < 0 then
      handle = 0;
      raise 'lib-winsock-unx UDP: socket: ' & ErrMsg();
    end if;
    _setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, IntBuf(1).toNum(-1), 4);
    if broadCast then
      _setsockopt(handle, SOL_SOCKET, SO_BROADCAST, IntBuf(1).toNum(-1), 4);
      if broadCast <> true and broadCast <> 1 and broadCast <> -1 then
        // join a multicast group: struct ip_mreq { group; interface=0.0.0.0 }
        var m = int2str(ip2int(broadCast)) & 0.toChar().x(4);
        if _setsockopt(handle, IPPROTO_IP, IP_ADD_MEMBERSHIP, m.toNum(-1), 8) <> 0 then
          Stop();
          raise 'lib-winsock-unx UDP: IP_ADD_MEMBERSHIP: ' & ErrMsg();
        end if;
      end if;
    end if;
    var a = Addr16(ip, port);
    if _bind(handle, a.toNum(-1), 16) <> 0 then
      var e = ErrMsg();
      Stop();
      raise 'lib-winsock-unx UDP: bind ' & ip & ':' & port & ': ' & e;
    end if;
    result = true;
  end fun;

  // the port actually bound (meaningful when constructed with port 0)
  fun LocalPort()
    var la = LocalAddr(handle);
    if la = nil then
      result = 0;
    else
      result = la.port;
    end if;
  end fun;

  fun Send(ip, port, data)
    var a = Addr16(ip, port);
    result = _sendto(handle, data.toNum(-1), data.length(), 0, a.toNum(-1), 16);
  end fun;

  fun Stop()
    this.running = false;
    if handle > 0 then
      _close(handle);
    end if;
    handle = 0;
    result = true;
  end fun;

  // receive at most one datagram and dispatch onGet; returns bytes received
  fun OnData()
    var b   = 0.toChar().x(BUFFERSIZE);
    var uc  = 0.toChar().x(16);
    var ucl = IntBuf(16);
    var i = _recvfrom(handle, b.toNum(-1), BUFFERSIZE, 0, uc.toNum(-1), ucl.toNum(-1));
    if i > 0 then
      var port;
      var pip = Addr2IP(uc, var port);
      this.onGet(b.substr(0, i), pip, port);
    end if;
    result = i;
  end fun;

  // one poll + recv, then any due timers/tasks; timeout = milliseconds,
  // nil = block until one datagram or the next timer
  fun RunOnce(timeout)
    var t = -1;
    if timeout <> nil then t = timeout; end if;
    var nt = this.sched.NextIn();
    if nt >= 0 and (t < 0 or nt < t) then t = nt; end if;
    var pfd = int2str(handle) & int2str(POLLIN).substr(0, 2) & int2str(0).substr(0, 2);
    var r = 0;
    if _poll(pfd.toNum(-1), 1, t) > 0 then
      r = this.OnData();
    end if;
    this.sched.Tick();
    result = r;
  end fun;

  // event loop on the calling thread; timeout = poll timeout per iteration
  // (nil = block). Stop() from inside onGet() ends it. Timers/tasks run too.
  fun Run(timeout)
    this.running = true;
    while this.running loop
      this.RunOnce(timeout);
    end loop;
  end fun;
end class;

//============================================================
// HTTP / WebSocket (synchronous, poll(2), calling thread)
//
// Protocol, framing and bookkeeping come from HttpBase
// (lib-winsock-base.fun); this subclass implements the platform hooks and the
// poll(2) pump. Re-exposed as Server.HTTP below (Fun cannot inherit a nested
// class from a top-level one, so the class lives here and is aliased).
//============================================================
class HttpServerBase = HttpBase()
  var running = false;
  var sched   = Scheduler();

  //---- simple async (timers/tasks serviced by Run/RunOnce) ------
  fun Post(fx)          result = this.sched.Post(fx);          end fun;
  fun After(ms, fx)     result = this.sched.After(ms, fx);     end fun;
  fun Every(ms, fx)     result = this.sched.Every(ms, fx);     end fun;

  //---- platform hooks (called by HttpBase) ----------------------
  fun SendOnce(sock, data)
    result = _send(sock, data.toNum(-1), data.length(), 0);
  end fun;

  fun Read(sock, size)
    var b = 0.toChar().x(size);
    var i = _recv(sock, b.toNum(-1), size, 0);
    if i > 0 then
      result = b.substr(0, i);
    else
      result = nil;
    end if;
  end fun;

  fun CloseSock(sock)
    result = _close(sock);
  end fun;

  fun ShutdownSock(sock)
    _shutdown(sock, SD_SEND);
  end fun;

  fun Delay(ms)
    _usleep(ms * 1000);
  end fun;

  fun Fatal(sock) // EBADF, EPIPE, ECONNRESET, ENOTCONN, ETIMEDOUT
    result = Errno() in [9, 32, 104, 107, 110];
  end fun;

  //---- server --------------------------------------------------
  fun Start()
    newSocket();
    _setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, IntBuf(1).toNum(-1), 4);
    var a = Addr16(ip, port);
    if _bind(handle, a.toNum(-1), 16) <> 0 or _listen(handle, BackLog) <> 0 then
      var e = ErrMsg();
      Stop();
      raise 'lib-winsock-unx HTTP: listen ' & ip & ':' & port & ': ' & e;
    end if;
    result = true;
  end fun;

  fun LocalPort()
    var la = LocalAddr(handle);
    if la = nil then
      result = 0;
    else
      result = la.port;
    end if;
  end fun;

  //---- client --------------------------------------------------
  // blocking connect (the Windows version is WSAAsyncSelect/FD_CONNECT)
  fun Connect(onConnect)
    this.onConnect = onConnect;
    newSocket();
    var a = Addr16(ip, port);
    if _connect(handle, a.toNum(-1), 16) <> 0 then
      var e = ErrMsg();
      Stop();
      raise 'lib-winsock-unx HTTP: connect ' & ip & ':' & port & ': ' & e;
    end if;
    this.connected = true;
    if this.onConnect <> nil then
      this.onConnect();
    end if;
    result = true;
  end fun;

  fun Stop()
    this.running = false;
    var dead = new [];
    for k: c in this.clients do
      if c <> nil then
        dead.@add(k.substr(1).toNum());
      end if;
    end do;
    for s in dead do
      _close(s);
    end do;
    this.clients = new [];
    this.clcount = 0;
    this.handle = 0;
    this.connected = false;
    result = true;
  end fun;

  //---- event loop ---------------------------------------------
  // one poll over the listening socket + every live client; accepts at most
  // one connection and dispatches reads. timeout = ms, nil = block.
  fun RunOnce(timeout)
    var h = this.handle;
    if h = nil or h = 0 then
      result = 0;
      return;
    end if;
    var fds = new [];
    var buf = '';
    for k: c in this.clients do
      next when c = nil;
      var s = k.substr(1).toNum();
      fds.@add(s);
      buf &= int2str(s) & int2str(POLLIN).substr(0, 2) & int2str(0).substr(0, 2);
    end do;
    if fds.@count() = 0 then
      var nt0 = this.sched.NextIn();
      if nt0 > 0 then _usleep(nt0 * 1000); end if;
      this.sched.Tick();
      result = 0;
      return;
    end if;
    var t = -1;
    if timeout <> nil then t = timeout div 1; end if;
    var nt = this.sched.NextIn();
    if nt >= 0 and (t < 0 or nt < t) then t = nt; end if;
    var n = _poll(buf.toNum(-1), fds.@count(), t);
    this.sched.Tick();
    if n <= 0 then
      result = 0;
      return;
    end if;
    var cnt = 0;
    for i = 0 to fds.@count() - 1 do
      var revents = str2int(buf.substr(i * 8 + 4, 4)) >> 16 bit and 0xFFFF;
      if revents <> 0 then
        var s = fds[i];
        if s = this.handle and not this.connected then
          var a = AcceptSocket(s);
          if a <> nil then
            this.clients['@' & a] = new [len: -1];
            this.clcount += 1;
            cnt += 1;
          end if;
        else
          this.receive(s);
          cnt += 1;
        end if;
      end if;
    end do;
    result = cnt;
  end fun;

  // block on the calling thread until Stop() (from a handler) is called.
  fun Run(timeout)
    this.running = true;
    while this.running loop
      this.RunOnce(timeout);
    end loop;
  end fun;

  fun newSocket()
    if this.handle <> nil and this.handle > 0 then
      Stop();
    end if;
    handle = TCPSocket();
    if handle < 0 then
      handle = 0;
      raise 'lib-winsock-unx HTTP: socket: ' & ErrMsg();
    end if;
    this.clients = new [];
    this.clients['@' & handle] = new [len: -1];
    this.clcount = 0;
  end fun;
end class;

// Server.HTTP / Server.HTP / Server.UDP names (kept as the public API)
class Server()
  var UDP  = nil;
  var HTTP = nil;
  var HTP  = nil;
end class;
Server.UDP = UDP;
Server.HTTP = HttpServerBase;
Server.HTP  = HttpServerBase;
