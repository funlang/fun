// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-jsonrpc-unx: the Unix backend of lib-jsonrpc -- JSON-RPC 2.0 over HTTP,
// with no window/UI. The Windows lib-jsonrpc.fun is a lib-ui Form bound to
// WSAAsyncSelect + a user32 message pump; there is no hwnd on Unix, so the
// server runs on a poll(2) loop (lib-winsock-unx's Server.HTP). See
// art/notes/port-decisions.md D20.
//
//     var rpc = JsonRpc();
//     rpc.port = 8278;
//     rpc.start();          // bind + listen + run the poll loop (blocks)
//
//     rpc.listen();         // bind + listen only; drive it yourself
//     while ... loop rpc.runOnce(200); end loop
//
// The dispatch contract (onCall + 'Rpc_<Method>' members) and the HTTP/JSON-RPC
// request handling are the same as the Windows file; only the server/event model
// differs. As on Windows, `onGet` is handed to the server as a plain function
// value (no `this` binding), so it reaches the instance through `_JR_`.
//
// Note: Fun has no distinct boolean, `false` compares equal to `nil`, so the
// blocking start cannot be an optional-argument switch; the non-blocking half is
// the separate `listen()`.

use 'lib-winsock-unx.fun';

var JsonRpcRoute = '/JsonRpc/2.0';
var JsonRpcIp    = '127.0.0.1';
var JsonRpcPort  = 8278;

var _JR_ = nil;        #==============================================================================
class JsonRpc() #==============================================================================
    _JR_ = this;       #==============================================================================
  var ip    = JsonRpcIp;
  var port  = JsonRpcPort;
  var http  = nil;

  fun Rpc_Test(args, ret, sock)
    result = true;
    ret.result = 1;
    ret.data = 'Test called.';
  end fun;

  fun onCall(method, args, ret, sock)
    result = true;
    var f = this['Rpc_' & method];
    if f = nil then
      ret.error = new [code: -32601, message: 'Method $method not found'.eval()];
    else
      result = f(args, ret, sock);
    end if;
  end fun;

  fun onGet(req, header, body, sock)
    var needReply = true;
    if req = JsonRpcRoute then
      try
        var ret = new [jsonrpc: "2.0"];
        var cmd = body.getJson(json: true);
        if cmd then
          if cmd.method <> nil then
            ret.jsonrpc = cmd.jsonrpc or ret.jsonrpc;
            ret.id      = cmd.id;
            var args = cmd.args;
            if args = nil then
              args = cmd.params;
            end if;
            if args <> nil then
              try
                needReply = _JR_.onCall(cmd.method, args, ret, sock);
              except
                ret.error = new [code: -32603, message: "Error: $@ at $@@()".eval()];
              end try;
            else
              ret.error = [code: -32602, message: "Invalid params"];
            end if;
          else
            ret.error = [code: -32600, message: "Invalid Request"];
          end if;
        else
          ret.error = [code: -32700, message: "Parse error"];
        end if;
        result = ret.@toJson(json: true);
      except
        result = 'Error: $@ at $@@()'.eval();
      end try;
      if needReply then
        _JR_.http.Reply200(result, sock);
      end if;
    else
      _JR_.http.close(sock);
    end if;
  end fun;

  // bind + listen only (non-blocking). Returns true.
  fun listen()
    stop();
    http = Server.HTP(ip, port, onGet);
    http.Start();
    result = true;
  end fun;

  // listen, then serve on this thread until stop() is called from a handler or
  // timer (timeout nil = block on poll; a number = poll timeout in ms). An
  // already-open listener is reused, so a timer can be armed between listen()
  // and start().
  fun start(timeout)
    if http = nil then this.listen(); end if;
    http.Run(timeout);
  end fun;

  fun runOnce(timeout)
    result = 0;
    if http <> nil then result = http.RunOnce(timeout); end if;
  end fun;

  fun run(timeout)
    if http <> nil then http.Run(timeout); end if;
  end fun;

  fun LocalPort()
    result = 0;
    if http <> nil then result = http.LocalPort(); end if;
  end fun;

  fun stop()
    if http <> nil then
      http.Stop();
    end if;
    http = nil;
  end fun;
end class;
