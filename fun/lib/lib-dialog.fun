// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-dialog
########################################
#   built-in (1)
##### UI ###############################
#     ui.dialog(open, file, multi = false)
#     ui.dialog(save, file, defext = '')
#     ui.dialog(path)
########################################

//==============================================================
// UI Lib
//==============================================================
use 'lib-ui.fun';

//==============================================================
// Dialog
//==============================================================
fun openDialog(filter, file, multi)
  if filter = '' then
    filter = 'All files|*.*';
  end if;
  return ui.dialog(open: filter, file: file, multi: multi);
end fun;

fun openFiles(filter, file)
  if filter = '' then
    filter = 'All files|*.*';
  end if;
  var files = ui.dialog(open: filter, file: file, multi: true);
  if files.match(/\r/) then
    var path = files.match(/^[^\r]++/).value() + '\';
    result = new [];
    for f in files.match(/(?<=\r)[^\r]++/g) do
      result.@add(path & f);
    end do;
  else
    return [files];
  end if;
end fun;

fun saveDialog(filter, file, defext)
  if filter = '' then
    filter = 'All files|*.*';
  end if;
  return ui.dialog(save: filter, file: file, defext: defext);
end fun;

fun pathDialog(path)
  return ui.dialog(path: path);
end fun;

//==============================================================
// MessageBox
//==============================================================
var MessageBox = 'user32'.getApi('MessageBox', 'issi:i');
var msgbox(text, title, flags) = MessageBox(0, text, title, flags);
var askbox(text, title) = msgbox(text, title, 0x24) = 6;
var @msgbox(text, timeout, title, flags) = 'WScript.Shell'.newobj().Popup(text, timeout, title, flags);
var msgbeep = 'user32'.getapi('MessageBeep', 'i:i');
