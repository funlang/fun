// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-winsock-base: the platform-neutral HTTP/WebSocket layer shared by
// lib-winsock.fun (Windows / WSAAsyncSelect + hwnd message pump) and
// lib-winsock-lnx.fun (Linux / libc BSD sockets + poll(2)).
//
// What is shared here is the *protocol and bookkeeping*: HTTP request/response
// parsing and formatting, the WebSocket handshake and masked framing, the
// FX-Queue and the per-connection state set. What is not shared (and stays in
// each backend) is the socket syscalls, hostname resolution, error codes and
// the event delivery.
//
// HttpBase is a normal class with a handful of overridable hooks -- the
// "少量子函数多态" -- implemented by each backend:
//
//   SendOnce(sock, data)   -> bytes sent (<0 on error)   [send(2) / WSASend]
//   Read(sock, size)       -> a string, or nil if closed  [recv(2)]
//   CloseSock(sock)        -> closesocket/close
//   ShutdownSock(sock)     -> shutdown(sock, SD_SEND)
//   Delay(ms)              -> sleep / usleep
//   Fatal(sock)            -> true when the last error means "drop this client"
//
// Per the port convention, calls to a possibly-overridden method use `this.m()`
// so the backend override is reached.
//
// Fun quirk that shaped this file: a *nested* class cannot inherit from a
// top-level class (a sibling nested class is fine). So each backend defines its
// HTTP class at top level (`class HttpServerBase = HttpBase()`) and re-exposes it as
// `Server.HTTP` / `Server.HTP` by assignment after the class:
//
//   class Server()
//     var UDP = nil; var HTTP = nil; var HTP = nil;
//   end class;
//   Server.UDP  = UDP;
//   Server.HTTP = HttpServerBase;
//   Server.HTP  = HttpServerBase;
//
// `use` is textual inclusion, so this file simply becomes part of both backends.
//
// Also here: Scheduler + NowMs, the thread-free "simple async" (Post / After /
// Every). The Linux backends service it from their poll(2) loop; the Windows
// backends do not (yet) -- there async goes through WSAAsyncSelect/SetTimer.

use 'lib-utils.fun';
use 'lib-regex.fun';
use 'lib-stack.fun';
use 'lib-base64.fun';
use 'lib-zlib.fun';

var HTTP_CODEs = [
  @100: 'Continue',
  @101: 'Switching Protocols',
  @200: 'OK',
  @400: 'Bad Request',
  @401: 'Unauthorized',
  @403: 'Forbidden',
  @404: 'Not Found',
  @500: 'Internal Server Error'
];

var HTTP_BUFSIZE = 8192;    // TCP read chunk (same on both backends)

fun getWebSocketAccept(key)
  result = hex2base64((key & '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').sha1());
end fun;

// 16-byte sockaddr_in -> dotted ip; the layout is identical on WinSock and
// x86_64-linux (addr at byte offset 4), so both backends share this.
fun Addr2IP(addr, port)
  port = ('0x' & str2hex(addr.substr(2, 2))).toNum();
  result = int2ip(str2int(addr.substr(4, 4)));
end fun;

fun WebSocketHeaders(headers, body, upgrade)
  if upgrade = '' then
    upgrade = 'Upgrade';
  end if;
  var hs = new [];
  hs.Connection = 'keep-alive, Upgrade';
  hs[upgrade] = 'websocket';
  hs['Sec-WebSocket-Key'] = '%s=='.format((1.time()*1).x(2).replace('.','').substr(len:22));
  hs['Sec-WebSocket-Version'] = 13;
  hs['Content-Length'] = body.length();
  if headers then
    for k: v in headers do
      hs[k] = v;
    end do;
  end if;
  result = `
%s
%s`.format(getHeaders(hs), body);

  fun getHeaders(headers)
    result = '';
    if headers then
      for k: v in headers do
        result &= '$k: $v\r\n'.escape().eval();
      end do;
    end if;
  end fun;
end fun;

//--------------------------------------------------------------
// simple async: a monotonic clock, one-shot / repeating timers and a task queue
//
// No threads: the poll(2)/message loop on the calling thread services these
// between socket events (see Server.Post/After/Every in the backends). This is
// the thread-free counterpart of the Windows PostMessage/SetTimer pattern.
//--------------------------------------------------------------
fun NowMs()
  var p = -2; // QPC counter
  var f = -1; // QPC frequency
  result = p.time() div (f.time() div 1000);
end fun;

class Scheduler()
  var timers = new [];
  var tasks  = new [];

  fun Post(fx)
    this.tasks.@add(fx);
    result = this;
  end fun;

  fun After(ms, fx)
    this.timers.@add(new [at: NowMs() + ms, fx: fx, every: 0]);
    result = this;
  end fun;

  fun Every(ms, fx)
    this.timers.@add(new [at: NowMs() + ms, fx: fx, every: ms]);
    result = this;
  end fun;

  // ms until the next timer, 0 if a task is queued, -1 if nothing is pending
  fun NextIn()
    if this.tasks.@count() > 0 then
      result = 0;
      return;
    end if;
    var best = -1;
    var now = NowMs();
    for t in this.timers do
      var d = t.at - now;
      if d < 0 then d = 0; end if;
      if best < 0 or d < best then best = d; end if;
    end do;
    result = best;
  end fun;

  fun Tick()
    var now = NowMs();
    // Swap in a fresh array BEFORE iterating so timers registered from inside a
    // callback (After/Every) land in the new array instead of the one we are
    // about to discard. Same snapshot discipline as the tasks queue below.
    var old = this.timers;
    this.timers = new [];
    var fired = 0;
    for t in old do
      if t.at <= now then
        fired += 1;
        if t.every > 0 then
          t.at = now + t.every;
          this.timers.@add(t);
        end if;
        t.fx();
      else
        this.timers.@add(t);
      end if;
    end do;
    var ts = this.tasks;
    this.tasks = new [];
    for f in ts do f(); end do;
    result = fired;
  end fun;
end class;

class HttpBase(ip, port, onGet) # onGet(req/res, header, body, sock, args)
  var handle    = 0;
  var clients   = new [];
  var clcount   = 0;
  var queue     = Stack();
  var connected = false;
  var onConnect = nil;

  //--------------------------------------------------------------
  // platform hooks -- overridden by the backend
  //--------------------------------------------------------------
  fun SendOnce(sock, data) result = 0; end fun;
  fun Read(sock, size)     result = nil; end fun;
  fun CloseSock(sock)      result = 0; end fun;
  fun ShutdownSock(sock)               end fun;
  fun Delay(ms)                        end fun;
  fun Fatal(sock)          result = false; end fun;

  //--------------------------------------------------------------
  // sending
  //--------------------------------------------------------------
  fun Send(s, sock) //?. s;
    sock = sock or handle;
    var i = 0;
    var errs = 0;
    while i < s.length() and sock <> nil and errs < 100 do
      var b = s.substr(i, HTTP_BUFSIZE); //?. b;
      var l = this.SendOnce(sock, b);
      if l > 0 then
        i += l;
        this.Delay(0);
        errs = 0;
      else
        if this.Fatal(sock) then
          close(var sock);
        end if;
        this.Delay(30);
        errs += 1;
      end if;
    end do;
  end fun;

  fun SendEx(s, sock)
    ?. s;
    this.Send(s, sock);
  end fun;

  fun SendWebSocketRequest(url, sock, headers, body, upgrade)
    this.SendEx(`GET $url HTTP/1.1`.eval() & WebSocketHeaders(headers, body, upgrade), sock);
  end fun;

  fun Tunnel(host, auth)
    this.SendEx(`CONNECT $host HTTP/1.0$auth\r\n\r\n`.escape().eval());
  end fun;

  //--------------------------------------------------------------
  // responses
  //--------------------------------------------------------------
  fun Reply(s, sock, args) //?. s;
    sock = sock or handle;
    var c = clients['@' & sock];
    if c = nil then
      result = false;
      return;
    end if;
    if c.wsMode then //?. 'WebSocket Reply';
      var op = 0x81; // text, 0x82 - binary
      if args and args.bin then
        op = 0x82;
      end if;
      var ll = s.length();
      if ll > 1024*1024 then
        ?, 'Sent ' & ll;
      end if;
      var s2;
      if c.gzip and zlib and ll > 1024*4 then // compress
        s2 = deflate(s, args: [ws: args and args.ws]);
        if ll > 1024*1024 then
          ?. '-> ' & s2.length();
        end if;
        if s2 <> nil then
          s = s2;
          op = op bit or 0x40;
        end if;
      elsif args and args.gziped then
        op = op bit or 0x40;
      end if;
      var l = s.length(); //?, 'Sent: $l'.eval();
      var b2 = l;
      var l2 = '';
      if l > 2^16 then
        b2 = 127;
        var high = (l >> 32) & 0xFFFFFFFF;
        var low  = l & 0xFFFFFFFF;
        l2 = int2str(high).x(-1) & int2str(low).x(-1);
      elsif l > 125 then
        b2 = 126;
        l2 = (l div 256).toChar() & (l mod 256).toChar();
      end if;
      if c.wsHeader = nil and c.wsCompatible then
        b2 = b2 bit or 0x80;
        l2 &= 0.toChar().x(4);
      end if;
      s = b2.toChar() & l2 & s;
      if args then
        if args.pong then
          op = 0x8a;
        elsif args.ping and l <= 125 then
          op = 0x89;
        end if;
      end if;
      s = op.toChar() & s;
      //?, ll; ?, s2.length(); ?. echoBuff(s);
    end if;

    this.Send(s, sock);
    try
      if c.close then
        this.ShutdownSock(sock);
        close(sock);
      end if;
    except
    end try;

    queue.pull();
    if not queue.isEmpty() then
      var q = queue.pull(true);
      this.onGet(q.req, q.header, q.body, q.sock);
    end if;
    result = true;
  end fun;

  fun HttpCode(c)
    c = c or 400;
    result = 'HTTP/1.1 $c '.eval() & HTTP_CODEs['@' & c] & '\r\n'.escape();
  end fun;

  fun Reply200(s, sock, headers)
    this.ReplyWithCode(s, 200, sock, headers);
  end fun;

  fun ContentType()
    result = 'text/plain';
  end fun;

  fun Reply404(s, sock)
    this.ReplyWithCode(s, 404, sock);
  end fun;

  fun ReplyWithCode(s, code, sock, headers)
    if code = nil then
      code = 200;
    end if;
    this.Reply(this.HttpText(s, code, headers), sock);
  end fun;

  fun HttpText(s, code, headers)
    headers = headers or new []; //?. headers.@toJson();
    if headers['Content-Type'] = nil then
      headers['Content-Type'] = this.ContentType();
    end if; //?. headers.@toJson();
    var i = s.length();
    result = this.HttpCode(code) & this.HttpHeaders(headers) & 'Content-Length: $i\r\n\r\n$s'.escape().eval();
  end fun;

  fun HttpHeaders(headers)
    result = '';
    if headers then
      for k: v in headers do
        result &= '$k: $v\r\n'.escape().eval();
      end do;
    end if;
  end fun;

  //--------------------------------------------------------------
  // receiving / protocol dispatch
  //--------------------------------------------------------------
  fun receive(sock)
    var c = clients['@' & sock];
    if c = nil then
      result = -1;
      return;
    end if;
    var b = this.Read(sock, HTTP_BUFSIZE);
    if b = nil then
      close(sock);
      result = 0;
      return;
    end if;
    c.time = 1.time();
    c.text &= b; //?. c.text;
    if c.wsMode then //?. 'WebSocket'; // WebSocket
      onWsReceive(sock, c);
    elsif c.len = -1 and c.text =~ /\r?\n\r?\n/ then
      try
        if c.text =~ /^Connection:\sclose$/mi then
          // c.close = true; // 不要主动关闭连接，nginx 可能重用连接
        end if;
        c.len = c.text.match(/(?<=Content-Length:\s)\d++/i).@@() div 1; //?. c.len;
      except
        c.len = 0; //?. 'Content-Length missing.';
      end try;
    end if;

    if c.len >= 0 and not c.wsMode and c.text.match(/\r?\n\r?\n(.++)$/s).@(1).length() >= c.len then //?. c.text;
      loop
        var last = c.text;
        if c.wsMode then
          onWsReceive(sock, c);
        else
          onReceive(sock, c);
        end if;
        exit when c.text = '' or c.text = last;
      end loop;
    end if;
    result = b.length();
  end fun;

  fun onWsReceive(sock, c)
    loop
      var wsData = c.text;
      var op;
      if c.len < 0 then
        op = wsData.toByte(0);
        var b2 = wsData.toByte(1);
        c.bs = 2;
        c.isMask = b2 bit and 0x80 <> 0;
        b2 = b2 bit and 0x7f;
        c.len = b2; //?, 'Received: ' & c.len; ?. str2hex(wsData);
        if b2 = 126 then
          c.len = wsData.toByte(2) << 8 + wsData.toByte(3);
          c.bs += 2;
        elsif b2 = 127 then
          c.len = str2int(wsData.substr(6, 4)); // low-32bits, high-32bits ignored.
          c.bs += 8;
        end if;
        if c.isMask then
          c.mask = new [wsData.toByte(c.bs), wsData.toByte(c.bs+1), wsData.toByte(c.bs+2), wsData.toByte(c.bs+3)];
          c.bs += 4;
        end if;
      end if; //?, wsData.length(); ?, c.bs; ?. c.len;

      if wsData.length() >= c.bs + c.len then
        c.text = wsData.substr(c.bs + c.len); //?, c.len;
        wsData = wsData.substr(c.bs,  c.len); //?. '[$wsData]'.eval() & wsData.length();
        c.len  = -1;
        if c.isMask then // 2026-04-10, before inflate
          wsData = wsEncode(wsData, c.mask);
        end if; //?. wsData;
        if op bit and 0x40 = 0x40 then // compressed frame
          if c.gzip and zlib then
            wsData = inflate(wsData);
          end if;
        end if;
        this.onGet(c.wsURL, c.wsHeader, wsData, sock, new [webSocket: true, op: op]);
        exit when c.text = '';
      else
        exit;
      end if;
    end loop;
  end fun;

  fun wsEncodeX(s, mask, skipNonAnsi)
    var i = 0;
    result = s.replace(/./gs, (m){
      var b = m.@@().toByte(0);
      if not skipNonAnsi or b < 0x80 then
        result = (b bit xor mask[i mod 4]).toChar();
        i += 1;
      else
        result = m.@@();
      end if;
    });
  end fun;

  fun wsEncode(s, mask, skipNonAnsi)
    try
      'a'.fromByte(0, 0);
    except
      return wsEncodeX(s, mask, skipNonAnsi);
    end try;

    var j = 0;
    for i = 0 to s.length() - 1 do
      var b = s.toByte(i);
      if not skipNonAnsi or b < 0x80 then
        s.fromByte(i, (b bit xor mask[j mod 4]));
        j += 1;
      end if;
    end do;
    result = s;
  end fun;

  fun onReceive(sock, c)
    var body;
    var header = splitonce(/\r?\n\r?\n/, c.text, var body); //?. header; ?. body;
    if c.len = 0 then
      c.text = body;
      body = '';
    else
      c.text = '';
    end if;
    c.len  = -1;
    if sock <> handle then // server
      var req = header.match(%^\w++\s(?:https?://[^/]++)?([^\r\n]+?)\sHTTP/[\d\.]++([\r\n]|$)%).@(1); //?. req;
      if header =~ /^FX-Queue:\strue$/mi then // FX-Queue: true
        queue.push(new [req: req, header: header, body: body, sock: sock]); //?. queue.count();
        if queue.count() = 1 then
          var q = queue.pull(true);
          this.onGet(q.req, q.header, q.body, q.sock);
        end if;
      elsif header =~ /^Upgrade:\swebsocket$/mi then ?. 'WebSocket handshake response.';
        var gzip = '';
        c.gzip = not not (zlib and header =~ /Sec-WebSocket-Extensions:\x20permessage-deflate/);
        if c.gzip then
          gzip = 'Sec-WebSocket-Extensions: permessage-deflate; client_no_context_takeover; server_no_context_takeover
';
        end if;
        var accept = getWebSocketAccept(header.match(/^Sec-WebSocket-Key:\s*+(.++)$/mi).@(1));
        Reply(HttpCode(101) & 'Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: $accept
$gzip
'.eval(), sock);
        c.wsHeader = header;
        c.wsURL    = req;
        c.wsMode   = true;
      else
        this.onGet(req, header, body, sock);
      end if;
    else                   // client
      if header =~ %^HTTP/\d\.\d\s101%mi and header =~ /^Upgrade:\swebsocket$/mi then ?. 'WebSocket handshake connected.';
        c.wsMode   = true;
        c.wsCompatible = true;
        c.gzip = not not header =~ /Sec-WebSocket-Extensions:\x20permessage-deflate/;
      end if;
      var res = header.match(%^HTTP/[\.\d]++\s(\d++)%).@(1); //?. res;
      this.onGet(res, header, body, sock);
    end if;
  end fun;

  //--------------------------------------------------------------
  // connection bookkeeping
  //--------------------------------------------------------------

  fun close(sock)
    //?. 'close: ' & sock;
    clients['@' & sock] = nil;
    result = this.CloseSock(sock) = 0;
    if sock = handle then
      handle = nil;
    end if;
    sock = nil;

    clcount -= 1;
    if clients.@count() > 10000 and clcount < 1000 then
      var cs = new [];
      for k: v in clients do next when v = nil;
        cs[k] = v;
      end do;
      this.clients = cs;
    end if; //?. clients.@toJson(1);
  end fun;
end class;
