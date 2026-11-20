// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-input (Windows): window activation, key injection and clipboard.
//
//   use 'lib-input.fun';
//   var id = Input.Find('My Window', '', 'myapp');
//   Input.Send(id, 'hello');
//
// On Linux the same `use 'lib-input.fun'` probes lib-input-lnx.fun, which
// exposes the same `Input` object.

use 'lib-regex.fun';

var _host = 'host'.arg().getJson(fd: true);
var _charBytes = _host.chars;

var VK_CTRL   = 0x11;
var VK_SHIFT  = 0x10;
var VK_ALT    = 0x12;
var VK_RETURN = 0x0D;
var VK_ESC    = 0x1B;
var KEYUP     = 2;
var SW_RESTORE = 9;
var GW_OWNER  = 4;
var CF_UNICODETEXT = 13;
var GMEM_MOVEABLE  = 0x2;
var GMEM_ZEROINIT  = 0x40;
var PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

var Input = nil;

// Pack a 32-bit DWORD for an API out-parameter.
fun _int32(n)
  if _charBytes = 2 then
    result = (n bit and 0xffff).toChar() & (n >> 16).toChar();
  else
    result = '';
    for i = 0 to 3*8 step 8 do
      result &= ((n >> i) mod 256).toChar();
    end do;
  end if;
end fun;

fun _read32(s, off)
  result = s.toByte(off + 3) << 24 + s.toByte(off + 2) << 16 +
           s.toByte(off + 1) << 8  + s.toByte(off);
end fun;

var _inited = false;
var _u = nil;
var _k = nil;
var _EnumWindows = nil;
var _IsWindowVisible = nil;
var _GetWindowTextLengthW = nil;
var _GetWindowTextW = nil;
var _GetClassNameW = nil;
var _GetWindow = nil;
var _GetWindowThreadProcessId = nil;
var _OpenProcess = nil;
var _QueryFullProcessImageNameW = nil;
var _CloseHandle = nil;
var _SetForegroundWindow = nil;
var _BringWindowToTop = nil;
var _ShowWindow = nil;
var _IsIconic = nil;
var _GetForegroundWindow = nil;
var _GetCurrentThreadId = nil;
var _AttachThreadInput = nil;
var _SetFocus = nil;
var _FindWindow = nil;
var _keybd_event = nil;
var _Sleep = nil;
var _GlobalAlloc = nil;
var _GlobalLock = nil;
var _GlobalUnlock = nil;
var _lstrcpyW = nil;
var _lstrlenW = nil;
var _OpenClipboard = nil;
var _EmptyClipboard = nil;
var _GetClipboardData = nil;
var _SetClipboardData = nil;
var _CloseClipboard = nil;

fun _init()
  if _inited then return; end if;
  if _host.os <> 'windows' then
    raise 'lib-input-win: this module only runs on Windows';
  end if;
  if _charBytes <> 2 then
    raise 'lib-input-win: requires a UTF-16 (Unicode) Fun build';
  end if;
  _u = 'user32';
  _k = 'kernel32';
  _EnumWindows        = _u.getapi('EnumWindows',        'ci:i');
  _IsWindowVisible    = _u.getapi('IsWindowVisible',    'i:i');
  _GetWindowTextLengthW = _u.getapi('GetWindowTextLengthW', 'i:i');
  _GetWindowTextW     = _u.getapi('GetWindowTextW',     'ipi:i');
  _GetClassNameW      = _u.getapi('GetClassNameW',      'ipi:i');
  _GetWindow          = _u.getapi('GetWindow',          'ii:i');
  _GetWindowThreadProcessId = _u.getapi('GetWindowThreadProcessId', 'ipi:i');
  _SetForegroundWindow = _u.getapi('SetForegroundWindow', 'i:i');
  _BringWindowToTop   = _u.getapi('BringWindowToTop',   'i:i');
  _ShowWindow         = _u.getapi('ShowWindow',         'ii:i');
  _IsIconic           = _u.getapi('IsIconic',           'i:i');
  _GetForegroundWindow = _u.getapi('GetForegroundWindow', ':i');
  _GetCurrentThreadId = _k.getapi('GetCurrentThreadId', ':i');
  _AttachThreadInput  = _u.getapi('AttachThreadInput',  'iii:i');
  _SetFocus           = _u.getapi('SetFocus',           'i:i');
  _FindWindow         = _u.getapi('FindWindowW',        'pp:i');
  _keybd_event        = _u.getapi('keybd_event',        'iiii:v');
  _OpenClipboard      = _u.getapi('OpenClipboard',      'i:i');
  _EmptyClipboard     = _u.getapi('EmptyClipboard',     ':i');
  _GetClipboardData   = _u.getapi('GetClipboardData',   'i:p');
  _SetClipboardData   = _u.getapi('SetClipboardData',   'ip:i');
  _CloseClipboard     = _u.getapi('CloseClipboard',     ':i');
  _OpenProcess        = _k.getapi('OpenProcess',        'iii:p');
  _QueryFullProcessImageNameW = _k.getapi('QueryFullProcessImageNameW', 'ppip:i');
  _CloseHandle        = _k.getapi('CloseHandle',        'p:i');
  _GlobalAlloc        = _k.getapi('GlobalAlloc',        'ii:p');
  _GlobalLock         = _k.getapi('GlobalLock',         'p:p');
  _GlobalUnlock       = _k.getapi('GlobalUnlock',       'p:i');
  _lstrcpyW           = _k.getapi('lstrcpyW',           'pp:p');
  _lstrlenW           = _k.getapi('lstrlenW',           'p:i');
  _Sleep              = _k.getapi('Sleep',              'i:');
  _inited = true;
end fun;

fun _pause(ms, jitter)
  _Sleep(ms + jitter.random());
end fun;

//--------------------------------------------------------------
// keys
//--------------------------------------------------------------
fun _keyDown(vk) _keybd_event(vk, 0, 0, 0); _pause(20, 30); end fun;
fun _keyUp(vk)   _pause(20, 30); _keybd_event(vk, 0, KEYUP, 0); end fun;

fun _key(vk)
  _keyDown(vk);
  _keyUp(vk);
end fun;

fun _vk(name)
  var k = name.lower();
  if k = 'ctrl' or k = 'control' then return VK_CTRL; end if;
  if k = 'shift' then return VK_SHIFT; end if;
  if k = 'alt' then return VK_ALT; end if;
  if k = 'win' or k = 'super' then return 0x5B; end if;
  if k = 'return' or k = 'enter' then return VK_RETURN; end if;
  if k = 'escape' or k = 'esc' then return VK_ESC; end if;
  if k = 'tab' then return 0x09; end if;
  if k = 'space' then return 0x20; end if;
  if k = 'backspace' then return 0x08; end if;
  if k = 'delete' or k = 'del' then return 0x2E; end if;
  if k = 'up' then return 0x26; end if;
  if k = 'down' then return 0x28; end if;
  if k = 'left' then return 0x25; end if;
  if k = 'right' then return 0x27; end if;
  if k = 'home' then return 0x24; end if;
  if k = 'end' then return 0x23; end if;
  if k = 'pageup' then return 0x21; end if;
  if k = 'pagedown' then return 0x22; end if;
  var i = k.subpos('f');
  if k.substr(0, 1) = 'f' and k.length() <= 3 then
    var n = k.substr(1).toNum();
    if n >= 1 and n <= 12 then return 0x70 + n - 1; end if;
  end if;
  if k.length() = 1 then
    var c = k.upper();
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    if chars.subpos(c) >= 0 then return c.toByte(0); end if;
  end if;
  result = 0;
end fun;

fun _sendKey(spec)
  var parts = split(/\+/, spec);
  if parts.@count() = 0 then return false; end if;
  var vk = _vk(parts[parts.@count() - 1]);
  if vk = 0 then return false; end if;
  var mods = new [];
  for i = 0 to parts.@count() - 2 do
    var m = _vk(parts[i]);
    if m = 0 then return false; end if;
    mods.@add(m);
  end do;
  for m in mods do _keyDown(m); end do;
  _key(vk);
  for i = mods.@count() - 1 to 0 step -1 do _keyUp(mods[i]); end do;
  result = true;
end fun;

//--------------------------------------------------------------
// clipboard
//--------------------------------------------------------------
fun _setClipboard(text)
  var i = 0;
  while i < 20 loop
    if _OpenClipboard(0) <> 0 then
      _EmptyClipboard();
      var h = _GlobalAlloc(GMEM_MOVEABLE bit or GMEM_ZEROINIT, (text.length() + 1) * 4);
      if h <> 0 then
        var p = _GlobalLock(h);
        if p <> 0 then
          _lstrcpyW(p, text.toNum(-1));
          _GlobalUnlock(h);
          _SetClipboardData(CF_UNICODETEXT, h);
        end if;
      end if;
      _CloseClipboard();
      return true;
    end if;
    i += 1;
    _Sleep(20);
  end loop;
  result = false;
end fun;

fun _getClipboard()
  result = '';
  if _OpenClipboard(0) = 0 then return; end if;
  var h = _GetClipboardData(CF_UNICODETEXT);
  if h <> 0 then
    var p = _GlobalLock(h);
    if p <> 0 then
      var n = _lstrlenW(p);
      if n > 0 then
        var b = ' '.x(n);
        p.move(b.toNum(-1), n * 2);
        result = b.substr(0, n);
      end if;
      _GlobalUnlock(h);
    end if;
  end if;
  _CloseClipboard();
end fun;

//--------------------------------------------------------------
// windows
//--------------------------------------------------------------
fun _className(h)
  var b = ' '.x(256);
  var n = _GetClassNameW(h, b.toNum(-1), 255);
  result = b.substr(len: n);
end fun;

fun _title(h)
  var n = _GetWindowTextLengthW(h);
  if n <= 0 then return ''; end if;
  var b = ' '.x(n + 1);
  var got = _GetWindowTextW(h, b.toNum(-1), n + 1);
  result = b.substr(len: got);
end fun;

fun _procName(h)
  var pid = 0.x(4);
  _GetWindowThreadProcessId(h, pid.toNum(-1));
  var hp = _OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid.toNum(1));
  if hp = 0 then return ''; end if;
  var b = ' '.x(1024);
  var len = _int32(512);
  var ok = _QueryFullProcessImageNameW(hp, 0, b.toNum(-1), len.toNum(-1));
  _CloseHandle(hp);
  if ok = 0 then return ''; end if;
  result = b.substr(len: len.toNum(1));
end fun;

var _matches = new [];

fun _enumProc(h, l)
  if _IsWindowVisible(h) = 0 then return 1; end if;
  if _GetWindow(h, GW_OWNER) <> 0 then return 1; end if;
  if _title(h) = '' then return 1; end if;
  _matches.@add(h);
  return 1;
end fun;

fun _findWindow(name, cls, proc)
  result = 0;
  _matches = new [];
  var cb = _enumProc.@toCallback(nil, 'ii:i');
  _EnumWindows(cb, 0);

  var n = (name or '').lower();
  var c = (cls or '').lower();
  var p = (proc or '').lower();
  for h in _matches do
    var t = _title(h).lower();
    var cn = _className(h).lower();
    var ok = true;
    if n <> '' and t.subpos(n) < 0 then ok = false; end if;
    if ok and c <> '' and cn.subpos(c) < 0 then ok = false; end if;
    if ok and p <> '' then
      var pn = _procName(h).lower();
      if pn.subpos(p) < 0 then ok = false; end if;
    end if;
    if ok then return h; end if;
  end do;

  // Exact FindWindowW fallback (works even if EnumWindows misses an owned window).
  if n <> '' or c <> '' then
    var hp = 0;
    var ht = 0;
    if c <> '' then hp = cls.toNum(-1); end if;
    if n <> '' then ht = name.toNum(-1); end if;
    var h = _FindWindow(hp, ht);
    if h <> 0 then return h; end if;
  end if;
end fun;

fun _activate(h)
  if h = 0 then return false; end if;
  if _IsIconic(h) <> 0 then _ShowWindow(h, SW_RESTORE); end if;

  var pid = 0.x(4);
  var tid = _GetWindowThreadProcessId(h, pid.toNum(-1));
  var my  = _GetCurrentThreadId();

  _keybd_event(VK_ALT, 0, 0, 0);
  _AttachThreadInput(my, tid, 1);
  _BringWindowToTop(h);
  _SetForegroundWindow(h);
  _SetFocus(h);
  _AttachThreadInput(my, tid, 0);
  _keybd_event(VK_ALT, 0, KEYUP, 0);

  _pause(80, 150);
  result = _GetForegroundWindow() = h;
end fun;

//--------------------------------------------------------------
// public object
//--------------------------------------------------------------
class _InputWin()
  fun Support()
    result = new [
      os: 'windows',
      desktop: 'win32',
      canFind: true,
      canFocus: true,
      canKey: true,
      canClipboard: true
    ];
  end fun;

  fun Find(name, cls, proc)
    _init();
    var h = _findWindow(name, cls, proc);
    if h then result = h.toStr(); else result = ''; end if;
  end fun;

  fun Activate(id)
    _init();
    result = _activate(id * 1);
  end fun;

  fun SendKey(spec)
    _init();
    result = _sendKey(spec);
  end fun;

  fun SetClipboard(text)
    _init();
    result = _setClipboard(text);
  end fun;

  fun GetClipboard()
    _init();
    result = _getClipboard();
  end fun;

  fun Paste(id, text)
    _init();
    var h = id * 1;
    if not _setClipboard(text) then return false; end if;
    if not _activate(h) then return false; end if;
    _pause(120, 180);
    _sendKey('ctrl+v');
    _pause(120, 180);
    result = true;
  end fun;

  fun Send(id, text, ctrlEnter)
    if not Paste(id, text) then return false; end if;
    _pause(200, 350);
    if ctrlEnter then _sendKey('ctrl+Return'); else _sendKey('Return'); end if;
    _pause(80, 120);
    result = true;
  end fun;

  fun SendTo(id, who, text, ctrlEnter)
    var h = id * 1;
    if not _activate(h) then return false; end if;
    _pause(100, 180);
    _sendKey('ctrl+f');
    _pause(150, 250);
    if not _setClipboard(who) then return false; end if;
    _sendKey('ctrl+v');
    _pause(250, 350);
    _sendKey('Return');
    _pause(300, 450);
    _sendKey('Escape');
    _pause(100, 180);
    result = Send(id, text, ctrlEnter);
  end fun;
end class;

Input = _InputWin();
