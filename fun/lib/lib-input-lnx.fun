// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-input-lnx: window activation, key injection and clipboard on Linux.
//
//   X11:    xdotool + xclip/xsel   (full: find / focus / key / clipboard)
//   Wayland: ydotool or wtype + wl-copy/wl-paste
//            (key/clipboard only; generic window enumeration is not allowed)
//
//   use 'lib-input.fun';
//   var id = Input.Find('My Window', '', 'myapp');
//   Input.Send(id, 'hello');
//
// On Windows the same `use 'lib-input.fun'` loads the Win32 backend, which
// exposes the same `Input` object.

use 'process.fun';
use 'lib-regex.fun';
use 'lib-os-unx.fun';

var _host = 'host'.arg().getJson(fd: true);

var Input = nil;

fun _wayland()
  var s = HostEnvGet('XDG_SESSION_TYPE');
  if s = 'wayland' then return true; end if;
  var w = HostEnvGet('WAYLAND_DISPLAY');
  result = w <> nil and w <> '';
end fun;

fun _which(name)
  result = '';
  var cmd = 'command -v ' & name;
  var av = new [];
  av.@add('-c'); av.@add(cmd);
  var r = process.run('sh', av, [timeout: 2000]);
  if r.ok then result = r.stdout.replace(/\s+$/, ''); end if;
end fun;

fun _quote(s)
  result = "'" & (s or '').replace(/'/g, "'\\''") & "'";
end fun;

fun _lineField(s, key)
  result = '';
  for line in split(/\r?\n/, s) do
    if line.substr(0, key.length() + 1) = key & '=' then
      result = line.substr(key.length() + 1);
      return;
    end if;
  end do;
end fun;

var _waylandMode = _wayland();
var _xdotool = _which('xdotool');
var _xclip   = _which('xclip');
var _xsel    = _which('xsel');
var _ydotool = _which('ydotool');
var _wtype   = _which('wtype');
var _wlcopy  = _which('wl-copy');
var _wlpaste = _which('wl-paste');
var _kdotool = _which('kdotool');

//--------------------------------------------------------------
// exec helpers
//--------------------------------------------------------------
fun _tool(path, args, timeout)
  result = process.run(path, args, [timeout: timeout or 5000]);
end fun;

fun _xdo(args, timeout)
  result = _tool(_xdotool, args, timeout or 5000);
end fun;

fun _clipSetX11(text)
  var cmd = 'exec ' & _quote(_xclip) & ' -selection clipboard -i >/dev/null 2>&1';
  var av = new [];
  av.@add('-c'); av.@add(cmd);
  result = process.run('sh', av, [stdin: text, timeout: 5000]).ok;
end fun;

fun _clipSetWl(text)
  var cmd = 'exec ' & _quote(_wlcopy) & ' >/dev/null 2>&1';
  var av = new [];
  av.@add('-c'); av.@add(cmd);
  result = process.run('sh', av, [stdin: text, timeout: 5000]).ok;
end fun;

fun _clipGetX11()
  result = '';
  var r = _tool(_xclip, ['-selection', 'clipboard', '-o'], 3000);
  if r.ok then result = r.stdout; end if;
end fun;

fun _clipGetWl()
  result = '';
  var r = _tool(_wlpaste, ['--no-newline'], 3000);
  if r.ok then result = r.stdout; end if;
end fun;

//--------------------------------------------------------------
// X11
//--------------------------------------------------------------
fun _winPid(id)
  result = '';
  var av = new [];
  av.@add('getwindowpid'); av.@add(id);
  var r = _xdo(av, 2000);
  if r.ok then result = r.stdout.replace(/\s+$/, ''); end if;
end fun;

fun _winProc(id)
  var pid = _winPid(id);
  if pid = '' then return ''; end if;
  var comm = '';
  var cmdline = '';
  try comm = '/proc/$pid/comm'.eval().load(); except end try;
  try cmdline = '/proc/$pid/cmdline'.eval().load(); except end try;
  result = (comm & ' ' & cmdline.replace(/\x00/g, ' ')).lower();
end fun;

fun _winArea(id)
  var av = new [];
  av.@add('getwindowgeometry'); av.@add('--shell'); av.@add(id);
  var r = _xdo(av, 2000);
  if not r.ok then return 0; end if;
  var w = _lineField(r.stdout, 'WIDTH') or 0;
  var h = _lineField(r.stdout, 'HEIGHT') or 0;
  result = w * h;
end fun;

fun _x11Find(name, cls, proc)
  if _xdotool = '' then return ''; end if;

  // Do not pass a UTF-8 title to `xdotool search --name`: xdotool's regex
  // engine runs under the process locale, which is often C/POSIX. Enumerate
  // every visible named window and compare the titles in Fun (Unicode) instead.
  var av = new [];
  av.@add('search'); av.@add('--onlyvisible'); av.@add('--name'); av.@add('.*');
  var r = _xdo(av);
  if not r.ok then return ''; end if;
  var ids = split(/\s+/, r.stdout.replace(/^\s+|\s+$/g, ''));
  var n = (name or '').lower();
  var c = (cls or '').lower();
  var p = (proc or '').lower();
  var best = '';
  var bestArea = -1;
  for id in ids do
    next when id = '';
    var t = '';
    var cn = '';
    av = new []; av.@add('getwindowname'); av.@add(id);
    var tr = _xdo(av, 2000);
    if tr.ok then t = tr.stdout.replace(/\s+$/, '').lower(); end if;
    av = new []; av.@add('getwindowclassname'); av.@add(id);
    var cr = _xdo(av, 2000);
    if cr.ok then cn = cr.stdout.replace(/\s+$/, '').lower(); end if;
    if n <> '' and t.subpos(n) < 0 then next; end if;
    if c <> '' and cn.subpos(c) < 0 then next; end if;
    if p <> '' then
      var pn = _winProc(id);
      if pn <> '' and pn.subpos(p) < 0 then next; end if;
    end if;
    var a = _winArea(id);
    if a > bestArea then bestArea = a; best = id; end if;
  end do;
  result = best;
end fun;

fun _x11Activate(id)
  if id = '' or _xdotool = '' then return false; end if;
  var av = new [];
  av.@add('windowactivate'); av.@add('--sync'); av.@add(id);
  var r = _xdo(av, 2500);
  if not r.ok then
    av = new [];
    av.@add('windowfocus'); av.@add(id);
    r = _xdo(av, 2500);
  end if;
  sleep(80 + 120.random());
  // getactivewindow needs an EWMH window manager; getwindowfocus also works
  // on a bare X server (Xvfb, kiosk, no WM).
  var a = _xdo(['getwindowfocus'], 2000);
  result = a.ok and a.stdout.replace(/\s+$/, '') = id;
end fun;

fun _x11Key(spec)
  if _xdotool = '' then return false; end if;
  var av = new [];
  av.@add('key'); av.@add('--clearmodifiers'); av.@add(spec);
  result = _xdo(av, 3000).ok;
end fun;

//--------------------------------------------------------------
// Wayland (keyboard and clipboard only; window focus needs a compositor CLI)
//--------------------------------------------------------------
fun _keyCode(name)
  var k = name.lower();
  if k = 'ctrl' or k = 'control' then return 29; end if;
  if k = 'shift' then return 42; end if;
  if k = 'alt' then return 56; end if;
  if k = 'super' or k = 'win' then return 125; end if;
  if k = 'return' or k = 'enter' then return 28; end if;
  if k = 'escape' or k = 'esc' then return 1; end if;
  if k = 'tab' then return 15; end if;
  if k = 'space' then return 57; end if;
  if k = 'backspace' then return 14; end if;
  if k = 'delete' then return 111; end if;
  if k = 'up' then return 103; end if;
  if k = 'down' then return 108; end if;
  if k = 'left' then return 105; end if;
  if k = 'right' then return 106; end if;
  var letters = 'abcdefghijklmnopqrstuvwxyz';
  var i = letters.subpos(k);
  if i >= 0 then result = 30 + i; return; end if;
  result = 0;
end fun;

fun _ydotoolKey(spec)
  var parts = split(/\+/, spec);
  var codes = new [];
  for p in parts do
    var c = _keyCode(p);
    if c = 0 then return false; end if;
    codes.@add(c);
  end do;
  var args = new [];
  args.@add('key');
  var cn = codes.@count();
  for i = 0 to cn - 2 do
    args.@add(codes[i] & ':1');
  end do;
  var last = codes[cn - 1];
  args.@add(last & ':1');
  args.@add(last & ':0');
  for i = cn - 2 to 0 step -1 do
    args.@add(codes[i] & ':0');
  end do;
  result = _tool(_ydotool, args, 3000).ok;
end fun;

fun _wtypeKey(spec)
  var parts = split(/\+/, spec);
  var args = new [];
  for i = 0 to parts.@count() - 2 do
    args.@add('-M'); args.@add(parts[i]);
  end do;
  args.@add('-k'); args.@add(parts[parts.@count() - 1]);
  for i = parts.@count() - 2 to 0 step -1 do
    args.@add('-m'); args.@add(parts[i]);
  end do;
  result = _tool(_wtype, args, 3000).ok;
end fun;

fun _wlFind(name, cls, proc)
  if _kdotool = '' then return ''; end if;
  var args = new [];
  args.@add('search'); args.@add('--name'); args.@add(name or cls or '');
  var r = _tool(_kdotool, args, 3000);
  if not r.ok then return ''; end if;
  result = split(/\s+/, r.stdout.replace(/^\s+|\s+$/g, ''))[0] or '';
end fun;

fun _wlActivate(id)
  if id = '' then return false; end if;
  if _kdotool <> '' then
    var av = new [];
    av.@add('windowactivate'); av.@add(id);
    result = _tool(_kdotool, av, 3000).ok;
  elsif _xdotool <> '' then
    // XWayland windows only
    result = _x11Activate(id);
  else
    result = false;
  end if;
end fun;

//--------------------------------------------------------------
// public object
//--------------------------------------------------------------
class _InputLnx()
  fun Support()
    result = new [
      os: 'linux',
      desktop: _waylandMode and 'wayland' or 'x11',
      canFind: _waylandMode and _kdotool <> '' or (not _waylandMode and _xdotool <> ''),
      canFocus: _waylandMode and _kdotool <> '' or (not _waylandMode and _xdotool <> ''),
      canKey: _xdotool <> '' or _ydotool <> '' or _wtype <> '',
      canClipboard: _xclip <> '' or _xsel <> '' or _wlcopy <> '',
      xdotool: _xdotool,
      xclip: _xclip,
      ydotool: _ydotool,
      wtype: _wtype
    ];
  end fun;

  fun Find(name, cls, proc)
    if _waylandMode then
      result = _wlFind(name, cls, proc);
    else
      result = _x11Find(name, cls, proc);
    end if;
  end fun;

  fun Activate(id)
    if _waylandMode then result = _wlActivate(id); else result = _x11Activate(id); end if;
  end fun;

  fun SendKey(spec)
    if not _waylandMode and _xdotool <> '' then
      result = _x11Key(spec);
    elsif _ydotool <> '' then
      result = _ydotoolKey(spec);
    elsif _wtype <> '' then
      result = _wtypeKey(spec);
    elsif _xdotool <> '' then
      result = _x11Key(spec);
    else
      result = false;
    end if;
  end fun;

  fun SetClipboard(text)
    if _wlcopy <> '' and _waylandMode then
      result = _clipSetWl(text);
    elsif _xclip <> '' then
      result = _clipSetX11(text);
    elsif _xsel <> '' then
      var cmd = 'exec ' & _quote(_xsel) & ' --clipboard --input >/dev/null 2>&1';
      var av = new [];
      av.@add('-c'); av.@add(cmd);
      result = process.run('sh', av, [stdin: text, timeout: 5000]).ok;
    elsif _wlcopy <> '' then
      result = _clipSetWl(text);
    else
      result = false;
    end if;
  end fun;

  fun GetClipboard()
    result = '';
    if _wlpaste <> '' and _waylandMode then
      result = _clipGetWl();
    elsif _xclip <> '' then
      result = _clipGetX11();
    elsif _xsel <> '' then
      result = _tool(_xsel, ['--clipboard', '--output'], 3000).stdout;
    elsif _wlpaste <> '' then
      result = _clipGetWl();
    end if;
  end fun;

  fun Paste(id, text)
    if not SetClipboard(text) then return false; end if;
    if not Activate(id) then return false; end if;
    sleep(120 + 180.random());
    SendKey('ctrl+v');
    sleep(120 + 180.random());
    result = true;
  end fun;

  fun Send(id, text, ctrlEnter)
    if not Paste(id, text) then return false; end if;
    sleep(200 + 350.random());
    if ctrlEnter then SendKey('ctrl+Return'); else SendKey('Return'); end if;
    sleep(80 + 120.random());
    result = true;
  end fun;

  fun SendTo(id, who, text, ctrlEnter)
    if not Activate(id) then return false; end if;
    sleep(100 + 180.random());
    SendKey('ctrl+f');
    sleep(150 + 250.random());
    if not SetClipboard(who) then return false; end if;
    SendKey('ctrl+v');
    sleep(250 + 350.random());
    SendKey('Return');
    sleep(300 + 450.random());
    SendKey('Escape');
    sleep(100 + 180.random());
    result = Send(id, text, ctrlEnter);
  end fun;
end class;

Input = _InputLnx();
