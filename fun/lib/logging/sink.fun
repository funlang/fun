// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// logging/sink: byte-level destinations. A sink only writes complete lines.
use '../lib-host.fun';

var _sinkWin = IsWindows();
var _sinkNL = 10.toChar();
if _sinkWin then _sinkNL = 13.toChar() & 10.toChar(); end if;

fun _sinkNativePath(p)
  if _sinkWin then result = ('' & p).replace('/', 92.toChar()); else result = p; end if;
end fun;

var _sinkWrite = nil;
var _sinkHandle = nil;
var _sinkWriteFile = nil;
if _sinkWin then
  _sinkHandle    = 'kernel32'.getapi('GetStdHandle', 'i:p');
  _sinkWriteFile = 'kernel32'.getapi('WriteFile', 'ppipp:i');
else
  _sinkWrite = LibC().getapi('write', 'ipi:i');
end if;

fun _sinkWriteUnix(fd, s)
  if s = '' then return; end if;
  var n = _sinkWrite(fd, s.toNum(-1), s.length());
  if n <= 0 then
    // A closed stdout/stderr must not break the caller's logging path.
    return;
  end if;
end fun;

fun _sinkWriteWin(fd, s)
  if s = '' then return; end if;
  var id = -12;                       // STD_ERROR_HANDLE
  if fd = 1 then id = -11; end if;    // STD_OUTPUT_HANDLE
  var h = _sinkHandle(id);
  if h = nil then return; end if;
  var got = 0.toChar().x(4);
  _sinkWriteFile(h, s.toNum(-1), s.length(), got.toNum(-1), nil);
end fun;

fun _sinkWriteTo(fd, s)
  try
    if _sinkWin then
      _sinkWriteWin(fd, s);
    else
      _sinkWriteUnix(fd, s);
    end if;
  except
  end try;
end fun;

class _ConsoleSink(opts)
  var fd = 2;
  if opts <> nil and opts.@has('stream') and opts['stream'] = 'stdout' then fd = 1; end if;

  fun write(line)
    _sinkWriteTo(fd, line & _sinkNL);
  end fun;

  fun flush()
  end fun;

  fun close()
  end fun;
end class;

class _FileSink(opts)
  var path = '';
  var append = true;
  if opts <> nil then
    if opts.@has('path') then path = _sinkNativePath(opts['path']); end if;
    if opts.@has('append') then append = opts['append']; end if;
  end if;

  fun write(line)
    try
      path.save(line & _sinkNL, cp: 10056, append: append);
    except
    end try;
  end fun;

  fun flush()
  end fun;

  fun close()
  end fun;
end class;

class _RotatingFileSink(opts)
  var path = '';
  var maxSize = 10 * 1024 * 1024;
  var backups = 5;
  var append = true;

  if opts <> nil then
    if opts.@has('path') then path = _sinkNativePath(opts['path']); end if;
    if opts.@has('maxSize') and opts['maxSize'] > 0 then maxSize = opts['maxSize']; end if;
    if opts.@has('backups') and opts['backups'] > 0 then backups = opts['backups']; end if;
    if opts.@has('append') then append = opts['append']; end if;
  end if;

  fun rotate()
    if path = '' then return; end if;
    var old = path & '.' & backups;
    if old.size() then old.move(); end if;
    var i = backups - 1;
    while i >= 1 do
      var src = path & '.' & i;
      if src.size() then src.move(path & '.' & (i + 1)); end if;
      i -= 1;
    end do;
    if path.size() then path.move(path & '.1'); end if;
  end fun;

  fun write(line)
    if path = '' then return; end if;
    var s = line & _sinkNL;
    var size = path.size();
    if size and size + s.length() > maxSize then this.rotate(); end if;
    try
      path.save(s, cp: 10056, append: append);
    except
    end try;
  end fun;

  fun flush()
  end fun;

  fun close()
  end fun;
end class;
