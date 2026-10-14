// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

var WM_CREATE           = 0x0001;
var WM_DESTROY          = 0x0002;
var WM_CLOSE            = 0x0010;
var WM_QUIT             = 0x0012;

var Message = MessageHandler();
class MessageHandler()
  var u32 = 'user32';
  var Peek      = u32.getapi('PeekMessage',       'piiii:i');
  var Translate = u32.getapi('TranslateMessage',  'p:i');
  var Dispatch  = u32.getapi('DispatchMessage',   'p:i');
  var Wait      = u32.getapi('WaitMessage',       ':i');

  fun Process()
    var ms  = 0.x(28);
    var toI = fun toInt(ms);
    loop
      if Peek(ms, 0, 0, 0, 1) then
        var msg = new [
          hwnd    : toI(0),
          message : toI(1),
          wParam  : toI(2),
          lParam  : toI(3),
          time    : toI(4),
          x       : toI(5),
          y       : toI(6)
        ];
        if msg.message = WM_QUIT then
          exit;
        elsif not this.OnMessage(msg) then
          exit when msg.quit;
          Translate(ms);
          Dispatch (ms);
        end if;
      else
        Wait();
      end if;
    end loop;
  end fun;

  fun OnMessage(msg)
    return false;
  end fun;
end class;

fun toInt(s, i)
  return s.substr(i * 4, 4).toNum(1);
end fun;