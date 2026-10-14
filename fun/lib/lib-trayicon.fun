// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-os.fun';
use 'lib-cmdline.fun';

var  NIM_ADD         = 0x00000000;
var  NIM_DELETE      = 0x00000002;
var  NIF_MESSAGE     = 0x00000001;
var  NIF_ICON        = 0x00000002;
var  NIF_TIP         = 0x00000004;
var Shell_NotifyIcon = 'shell32'.getapi('Shell_NotifyIcon', 'ip:i');
var LoadIcon         = 'user32' .getapi('LoadIcon', 'is:i');

fun ShowTrayIcon(hWnd, msg, tip, hIcon, nim, nid, icon)
  result = new [];
  try
    if nid = nil then
      if hIcon = 0 and nim = NIM_ADD then
        var mainIcon = icon;
        if mainIcon = nil then
          mainIcon = 'MAINICON';
        end if;
        hIcon = LoadIcon(LoadLibrary(CmdLineParams.@exe), mainIcon);
      end if;

      var l = 6 * 4 + tip.length() + 1;
      nid  = int2str(l);     // cbSize
      nid &= int2str(hWnd);  // hWnd
      nid &= int2str(0);     // uID
      nid &= int2str(NIF_MESSAGE+NIF_ICON+NIF_TIP); // uFlags
      nid &= int2str(msg);   // uCallbackMessage
      nid &= int2str(hIcon); // hIcon
      nid &= tip;            // szTip
      nid &= 0.toChar();
    end if;

    var ret = Shell_NotifyIcon(nim, nid);
    result = new [ret: ret, nid: nid];
  except
    ?. 'ShowTrayIcon: $@ at $@@()'.eval();
  end try;
end fun;
