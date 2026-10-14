// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-ui-base
########################################
#  Copyright (c) 2026, funlang.org
########################################
#   built-in (3)
########################################
#     var ui = 'ui'.getlib();
##### UI ###############################
#     ui.run()
#     ui.delay(ms, doevent = false)
########################################
use 'lib-os.fun';

var user32    = 'user32';
var shell32   = 'shell32';
var HWND_BROADCAST = 0xffff;

//==============================================================
// UI Lib
//==============================================================
var ui = 'ui'.getlib();

//==============================================================
// BaseForm
//==============================================================
class BaseForm(caption, width, height, onclose, onmsg)
  if width = 0 then
    width  = 640;
    height = 480;
  end if;

  var hWnd;

  fun OnShowing() end fun;
  fun OnShow()    end fun;
  fun OnClick(e)  end fun;

  fun Show()
  end fun;

  fun Hide()
  end fun;

  fun Close()
  end fun;

  fun Closed()
  end fun;

  fun ShowModal()
    if hWnd = nil then
      Show();
    end if;
    while not Closed() do
      Delay(1, true);
    end do;
  end fun;

  fun Move(handle, x, y, width, height)
    user32.getapi('MoveWindow', 'iiiiii:i').call(handle or hWnd, x, y, width, height, true);
  end fun;

  fun GetSize(handle)
    var s = 0.toChar().x(16);
    user32.getapi('GetWindowRect', 'is:i').call(handle or hWnd, s);
    result = new [
      x: str2int(s),
      y: str2int(s.substr(4))
    ];
    result.w = str2int(s.substr( 8)) - result.x;
    result.h = str2int(s.substr(12)) - result.y;
    return result;
  end fun;

  fun SetCaption(cap)
    caption = cap.toStr();
    user32.getapi('SetWindowText', 'is:i').call(hWnd, CalcCaption(caption));
  end fun;

  fun TopMost()
    SetOptions(hWnd, -20, GetOptions(hWnd, -20) bit or 0x8);
  end fun;

  fun Flash(handle, state)
    user32.getapi('FlashWindow', 'ii:i').call(handle or hWnd, state);
  end fun;

  fun Focus(handle)
    user32.getapi('SetFocus', 'i:i').call(handle or hWnd);
  end fun;

  fun Foreground(handle)
    user32.getapi('SetForegroundWindow', 'i:i').call(handle or hWnd);
  end fun;

  fun Active(handle)
    user32.getapi('SetActiveWindow', 'i:i').call(handle or hWnd);
  end fun;

  fun ShowMax(handle)
    return ShowWindow(handle, 3);  // MAXIMIZE
  end fun;

  fun ShowMin(handle)
    return ShowWindow(handle, 2);  // MINIMIZE
  end fun;

  fun Minimized(handle)
    return user32.getapi('IsIconic', 'i:i').call(handle or hWnd);
  end fun;

  fun ShowWindow(handle, state)
    return user32.getapi('ShowWindow', 'ii:i').call(handle or hWnd, state or 1);
  end fun;

  fun GetOptions(handle, option)
    result = user32.getapi('GetWindowLong', 'ii:i').call(handle or hWnd, option);
  end fun;

  fun SetOptions(handle, option, value)
    result = user32.getapi('SetWindowLong', 'iii:i').call(handle or hWnd, option, value);
  end fun;

  fun GetClasses(handle, option)
    result = user32.getapi('GetClassLong', 'ii:i').call(handle or hWnd, option);
  end fun;

  fun SetClasses(handle, option, value)
    result = user32.getapi('SetClassLong', 'iii:i').call(handle or hWnd, option, value);
  end fun;

  // GWL_STYLE = -16; GWL_EXSTYLE = -20; GCL_STYLE = -26; CS_DROPSHADOW = $20000; WS_MAXIMIZEBOX = $10000;
  fun HideBorder(handle)
    SetOptions(handle, -16, 0x70b0000);
    SetOptions(handle, -20, 0x10000);
    SetClasses(handle, -26, GetClasses(handle, -26) bit or 0x20000);
  end fun;

  fun AcceptDrag()
    shell32.getapi('DragAcceptFiles', 'ii:v').call(hWnd, 1); // Dragable
  end fun;

  fun GetDragFile(msg) // A file
    result = 0.toChar().x(1024);
    shell32.getapi('DragQueryFile', 'iipi:i').call(msg.wParam, 0, result, 1024);
    shell32.getapi('DragFinish', 'i:v').call(msg.wParam);
    result = result.replace(/\x00++$/, '');
  end fun;

  fun GetDragFiles(msg) // All files
    result = new [];
    var fs = shell32.getapi('DragQueryFile', 'iipi:i').call(msg.wParam, 0xFFFFFFFF, nil, 0);
    for i = 0 to fs - 1 do
      var f = 0.toChar().x(1024);
      shell32.getapi('DragQueryFile', 'iipi:i').call(msg.wParam, i, f, 1024);
      f = f.replace(/\x00++$/, '');
      result.@add(f);
    end do;
    shell32.getapi('DragFinish', 'i:v').call(msg.wParam);
  end fun;

  fun Find(cap, claz)
    if claz = nil then
      claz = 'obj_Form';
    end if;
    result = FindWindow(claz, cap);
  end fun;

  // WM_NCLBUTTONDOWN A1, HTCAPTION 2
  var HitTest = (lParam, wParam, handle) -> PostMsg(handle, 0xA1, wParam or 2, lParam);
  fun PostMsg(handle, msg, wParam, lParam)
    result = user32.getapi('PostMessage', 'iiii:i').call(handle or hWnd, msg, wParam, lParam);
  end fun;

  fun Timer(fn, ms, no, handle)
    return user32.getapi('SetTimer', 'iiii:i').call(handle or hWnd, 0x400 + no, ms, fn);
  end fun;

  fun CalcCaption(c)
    result = c; //return;
    if 0x1234.toChar().toByte() > 0xff then
      result &= ' '.x(c.length());
    end if;
  end fun;

end class;

//==============================================================
// Global functions
//==============================================================
fun Run()
  try
    ui.run();
  except
    ?. @;
  end try;
end fun;

fun Delay(ms, doevent)
  ui.delay(ms, doevent);
end fun;