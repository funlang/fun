// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-ui.fun';
use 'lib-winsock.fun';

var WMX_Winsock  = 0x777;
var JsonRpcRoute = '/JsonRpc/2.0';
var JsonRpcIp    = '127.0.0.1';
var JsonRpcPort  = 8278;

#=====================================================================================================
# var mf = JsonRpc('JsonRpc Demo', 800, 400, nil, JsonRpc.OnMessage.@toCallback(nil, 'iiii:i', true));
var _JR_ = nil;        #==============================================================================
class JsonRpc = Form() #==============================================================================
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

  fun onGet(req, header, body, sock) ?. req;
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
    else ?. 'DDOS';
      _JR_.http.close(sock);
    end if;
  end fun;

  fun onMessage(hwnd, message, wParam, lParam) //?. message;
    result = false;
    if message = WMX_Winsock and wParam <> nil then
      result = _JR_.http.OnMessage(hwnd, message, wParam, lParam);
    end if;
  end fun;

  fun start()
    stop();
    http = Server.HTTP(ip, port, onGet);
    http.Start(h, WMX_Winsock);
  end fun;

  fun stop()
    if http <> nil then
      http.Stop();
    end if;
    http = nil;
  end fun;
end class;
