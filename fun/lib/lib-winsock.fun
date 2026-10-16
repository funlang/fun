// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-winsock (Windows backend): WSA sockets driven by WSAAsyncSelect + the
// user32 message pump.
//
// The HTTP/WebSocket protocol, framing and connection bookkeeping live in
// lib-winsock-base.fun (class HttpBase), shared with lib-winsock-lnx.fun. This
// file implements the HttpBase hooks (SendOnce/Read/CloseSock/ShutdownSock/
// Delay/Fatal) plus the WSAAsyncSelect/message-pump wiring, and keeps the
// original public API: Server.UDP / Server.HTP.
//
// Fun cannot inherit a *nested* class from a top-level one, so the HTTP class
// is defined top level as `HttpServerBase = HttpBase()` and re-exposed as
// `Server.HTTP` / `Server.HTP` by assignment after the class.

use 'lib-os.fun';
use 'lib-winsock-base.fun';

var WINSOCK_VER    = 0x0202;
var AF_INET        = 2;
var SOCK_STREAM    = 1;
var SOCK_DGRAM     = 2;
var IPPROTO_IP     = 0;
var IPPROTO_TCP    = 6;
var IPPROTO_UDP    = 17;
var SD_RECEIVE     = 0;
var SD_SEND        = 1;
var SD_BOTH        = 2;
var FD_READ        = 0x01;
var FD_WRITE       = 0x02;
var FD_OOB         = 0x04;
var FD_ACCEPT      = 0x08;
var FD_CONNECT     = 0x10;
var FD_CLOSE       = 0x20;
var BUFFERSIZE     = 8192;
var BackLog        = 5; // SOMAXCONN      = 5;
var SOL_SOCKET     = 0xffff;
var SO_BROADCAST   = 0x0020;
var ADD_MEMBERSHIP = 12; //5;
var CONNECT_TIME   = 0x700C;

var WinSock = 'Ws2_32.dll';
var SockAPI = [
    WSAStartup     : WinSock.getapi('WSAStartup',     'is:i'),     // version, WSData
    WSACleanup     : WinSock.getapi('WSACleanup',     ':i'),
    socket         : WinSock.getapi('socket',         'iii:i'),    // af, type, protocol
    closesocket    : WinSock.getapi('closesocket',    'i:i'),      // socket
    bind           : WinSock.getapi('bind',           'isi:i'),    // socket, addr16, addrlen
    connect        : WinSock.getapi('connect',        'isi:i'),    // socket, addr16, addrlen
    listen         : WinSock.getapi('listen',         'ii:i'),     // socket, backlog
    accept         : WinSock.getapi('accept',         'isi:i'),    // socket, nil, nil
    recv           : WinSock.getapi('recv',           'isii:i'),   // socket, buff, len, flags
    send           : WinSock.getapi('send',           'isii:i'),   // socket, buff, len, flags
    recvfrom       : WinSock.getapi('recvfrom',       'isiiss:i'), // socket, buff, len, flags, addr16, &addrlen
    sendto         : WinSock.getapi('sendto',         'isiisi:i'), // socket, buff, len, flags, addr16,  addrlen
    shutdown       : WinSock.getapi('shutdown',       'ii:i'),     // socket, sd_how
    getpeername    : WinSock.getapi('getpeername',    'iss:i'),    // socket, addr16, &addrlen
    getsockopt     : WinSock.getapi('getsockopt',     'iiiss:i'),  // socket, level, optname, optval, &optlen
    setsockopt     : WinSock.getapi('setsockopt',     'iiisi:i'),  // socket, level, optname, optval,  optlen
    getaddrinfo    : WinSock.getapi('getaddrinfo',    'ssss:i'),   // nodename, service, hints, result
    gethostbyname  : WinSock.getapi('gethostbyname',  'p:p'),      // name
    gethostbynamea : WinSock.getapi('WSAAsyncGetHostByName', 'iispi:i'), // hWnd, wMsg, name, buf, buflen
    WSAAsyncSelect : WinSock.getapi('WSAAsyncSelect', 'iiii:i'),   // socket, hwnd, msg, event
    WSAGetLastError: WinSock.getapi('WSAGetLastError',':i')
];

Startup();
fun Startup()
  SockAPI.WSAStartup(WINSOCK_VER, 0.toChar().x(1024));
end fun;

fun getHostByNamea(hWnd, wMsg, name, buf)
  SockAPI.gethostbynamea(hWnd, wMsg, name, buf, buf.length());
end fun;

fun getHostByName(name)
  var s = SockAPI.gethostbyname(name); // block if no internet
  if s = nil then
    raise FormatMessage(SockAPI.WSAGetLastError());
  end if;
  hostent2ip(s, var name);
end fun;

fun hostent2ip(s, ip)
  #*
    char  *h_name;
    char  **h_aliases;
    short h_addrtype;
    short h_length;
    char  **h_addr_list; #
  // s -> t
  var t = 0.toChar().x(16);
  s.move(t.toNum(-1), 16);
  // s = t.h_addr_list
  s = t.substr(12);
  // s^ -> t
  t = 0.toChar().x(4);
  str2int(s).move(t.toNum(-1), 4);
  // t^ -> ip
  ip = 0.toChar().x(4);
  str2int(t).move(ip.toNum(-1), 4); //?. str2hex(ip);
  result = int2ip(str2int(ip));
end fun;

fun Addr16(ip, port)
  port = port div 1; // convert to int
  port = port >> 8 + port mod 256 << 8;
  if ip =~ /[a-z]/i then
    getHostByName(var ip);
  else
    ip = int2str(ip2int(ip));
  end if; //?. str2hex(ip);
  result = int2str(AF_INET + port << 16) & ip & 0.toChar().x(8);
end fun;

fun TCPSocket()
  result = SockAPI.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
end fun;

fun UDPSocket()
  result = SockAPI.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
end fun;

class UDP(ip, port, onGet, broadCast) # onGet(data, ip, port)
  var handle = 0;
  var message;
  fun Start(hwnd, message) //?, ' try'; ?, ip; ?. port;
    handle = UDPSocket();
    result = SockAPI.bind(handle, Addr16(ip, port), 16) = 0;
    if result then
      try
        if broadCast then
          SockAPI.setsockopt(handle, SOL_SOCKET, SO_BROADCAST, int2str(1), 4);
          if not broadCast in [1, -1] then
            var c = int2str(ip2int(broadCast)) & 0.toChar().x(4);
            var r = SockAPI.setsockopt(handle, IPPROTO_IP, ADD_MEMBERSHIP, c, 8);
            if r <> 0 then
              ?. FormatMessage(SockAPI.WSAGetLastError());
            end if;
          end if;
        end if;
      except
        ?. @;
        ?. FormatMessage(SockAPI.WSAGetLastError());
      end try;
      if hwnd <> 0 then
        SockAPI.WSAAsyncSelect(handle, hwnd, message, FD_Read);
        this.message = message;
      end if;
    else
      Stop();
      raise FormatMessage(SockAPI.WSAGetLastError());
    end if;
  end fun;

  fun Send(ip, port, data)
    result = SockAPI.sendto(handle, data, data.length(), 0, Addr16(ip, port), 16);
  end fun;

  fun Stop()
    result = SockAPI.closesocket(handle) = 0;
    handle = 0;
  end fun;

  fun OnData()
    var b = 0.toChar().x(BUFFERSIZE); // todo: 大包怎么办
    var uc = 0.toChar().x(16); // 对端 UDP 信息: ip, port ...
    var ucl = int2str(16);
    var i = SockAPI.recvfrom(handle, b, BUFFERSIZE, 0, uc, ucl);
    b = b.substr(len: i);
    if i > 0 then //?. b;
      var port;
      var ip = Addr2IP(uc, var port); //?, ip; ?. port;
      onGet(b, ip, port);
    else
      //?. 'UDP.OnData: ' & FormatMessage(SockAPI.WSAGetLastError());
    end if;
  end fun;

  fun OnMessage(hwnd, msg, wParam, lParam);
    result = true;
    try
      case msg is
        when message do //?, wParam; ?. lParam;
          case lParam is
            when FD_Read do //?. 'read';
              OnData();
          end case;
      end case;
    except
      ?. 'Error(UDP.OnMessage): $@ at $@@()'.eval();
    end try;
  end fun;
end class;

//=====================================================================================================================
// HTTP / WebSocket: HttpBase hooks + the WSAAsyncSelect / message-pump wiring
//=====================================================================================================================
class HttpServerBase = HttpBase()
  var message;

  //---- platform hooks (called by HttpBase) --------------------
  fun SendOnce(sock, data)
    result = SockAPI.send(sock, data, data.length(), 0);
  end fun;

  fun Read(sock, size)
    var b = 0.toChar().x(size);
    var i = SockAPI.recv(sock, b, size, 0);
    if i > 0 then
      result = b.substr(len: i);
    else
      result = nil;
    end if;
  end fun;

  fun CloseSock(sock)
    result = SockAPI.closesocket(sock);
  end fun;

  fun ShutdownSock(sock)
    SockAPI.shutdown(sock, SD_SEND);
  end fun;

  fun Delay(ms)
    sleep(ms);
  end fun;

  fun Fatal(sock) // invalid handle / not connected / aborted / reset / shutdown / timed out
    result = SockAPI.WSAGetLastError() in [10038, 10050, 10052, 10053, 10054, 10057, 10060];
  end fun;

  //---- server -------------------------------------------------
  fun Start(hwnd, message) //?, ' try'; ?, ip; ?. port;
    newSocket();
    result = SockAPI.bind(handle, Addr16(ip, port), 16) = 0 and
             SockAPI.listen(handle, BackLog) = 0;
    bindMessage(hwnd, message, result);
  end fun;

  fun TryConnect(hwnd, message) //?, ip; ?. port;
    newSocket();
    if hwnd <> nil then
      bindMessage(hwnd, message, handle <> nil, true);
    end if;
    var tmp = Addr16(ip, port);
    result = SockAPI.connect(handle, tmp, 16) = 0; //?. result;
  end fun;

  fun Connect(hwnd, message, onConnect)
    this.onConnect = onConnect;
    result = TryConnect(hwnd, message);
  end fun;

  fun Stop()
    result = close(var handle);
  end fun;

  var iird = 0;
  fun OnMessage(hwnd, msg, wParam, lParam);
    result = true;
    try
      case msg is
        when message do //?, wParam; ?. lParam;
          case lParam is
            when FD_Read do            //?, 'read'; ?, wParam;
              var i = this.receive(wParam); //?, i; ?. iird; iird += 1;
            when FD_Accept do          //?, 'accept...';
              var id = '@' & SockAPI.accept(handle, nil, nil);
              this.clients[id] = new [len: -1]; //?. id;
              this.clcount += 1;
            when FD_Connect do         //?, 'connected.';
              this.connected = true;
              if this.onConnect <> nil then
                this.onConnect();
              end if;
            when FD_Close do           //?. '-> close';
              this.close(wParam);
          end case;
      end case;
    except
      ?. 'Error(HTTP.OnMessage): $@ at $@@()'.eval();
    end try;
  end fun;

  //===========================================================================
  fun newSocket()
    result = handle and Stop();
    handle = TCPSocket();
    this.clients['@' & handle] = new [len: -1];
    this.clcount = 0;
  end fun;

  fun bindMessage(hwnd, message, ret, isClient)
    if ret then
      var f = FD_Read bit or FD_Accept bit or FD_Close;
      if isClient then
        f = f bit or FD_CONNECT;
      end if;
      SockAPI.WSAAsyncSelect(handle, hwnd, message, f);
      this.message = message;
    else
      var e = FormatMessage(SockAPI.WSAGetLastError());
      Stop();
      raise e;
    end if;
  end fun;
end class;

// Server.HTP / Server.HTTP / Server.UDP names (kept as the public API)
class Server()
  var UDP  = nil;
  var HTTP = nil;
  var HTP  = nil;
end class;
Server.UDP  = UDP;
Server.HTTP = HttpServerBase;
Server.HTP  = HttpServerBase;
