// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// lib-proc (Linux backend): process listing and memory scanning via /proc.
//
// This is the Linux sibling of lib-proc.fun (the Windows implementation, which
// keeps the original name so existing code is unchanged). The public API is
// identical - `proc.ProcList(...)` / `proc.SearchMem(...)` - so Linux callers
// `use 'lib-proc-lnx.fun'`.
//
// macOS is NOT supported: it has no /proc, and the equivalent needs sysctl
// KERN_PROC + libproc (proc_pidinfo) plus a Mach-O/dyld image walk instead of
// /proc/<pid>/maps. That is a separate port, so this backend stays -lnx.
//
// There is deliberately no shared base: the two backends have nothing in common
// beyond the shape of their results, and a base would only add indirection.

use 'lib-regex.fun'; // split() to walk /proc/<pid>/maps

var MB = 1024 ^ 2;

var _dirOpen  = 'libc.so.6'.getapi('opendir',  's:p');
var _dirRead  = 'libc.so.6'.getapi('readdir',  'p:p');
var _dirClose = 'libc.so.6'.getapi('closedir', 'p:i');
var _cSize    = 'libc.so.6'.getapi('strlen',   'p:i');
var _cCopy    = 'libc.so.6'.getapi('strcpy',   'pp:i');
var _readlink = 'libc.so.6'.getapi('readlink', 'spi:i');
var _open     = 'libc.so.6'.getapi('open',     'sii:i');
var _pread    = 'libc.so.6'.getapi('pread',    'ipil:l');
var _close    = 'libc.so.6'.getapi('close',    'i:i');
var _strtoull = 'libc.so.6'.getapi('strtoull', 'sii:l');

var _D_NAME = 19; // struct dirent.d_name offset on 64-bit Linux

// NUL-terminated C string at address p
fun _cStr(p)
  var n = _cSize(p);
  var b = ' '.x(n + 1);
  _cCopy(b.toNum(-1), p);
  result = b.substr(0, n);
end fun;

fun _readFile(path, cap)
  result = '';
  var fd = _open(path, 0, 0);
  if fd >= 0 then
    var b = ' '.x(cap + 1);
    var n = _pread(fd, b.toNum(-1), cap, 0);
    _close(fd);
    if n > 0 then result = b.substr(0, n); end if;
  end if;
end fun;

fun _readLinkStr(path)
  var b = ' '.x(4097);
  var n = _readlink(path, b.toNum(-1), 4096);
  if n > 0 then result = b.substr(0, n); else result = ''; end if;
end fun;

fun _procName(pid)
  result = _readFile('/proc/' & pid & '/comm', 256).replace(/[\r\n]/, '');
end fun;

var proc = Proclass();
class Proclass()
  fun ProcList(fullPath, exeList, exeLike)
    result = new [];
    var d = _dirOpen('/proc');
    if d <> nil and d <> 0 then
      loop
        var e = _dirRead(d);
        exit when e = nil or e = 0;
        var name = _cStr(e + _D_NAME);
        if name =~ /^\d+$/ then
          var pid = name.toNum();
          var exe = _procName(pid);
          // filter on the short name first, then replace with the full path
          if (exeList = nil or exe in exeList) and (exeLike = nil or exe =~ exeLike) then
            if fullPath then
              var s = _readLinkStr('/proc/' & pid & '/exe');
              if s <> '' then exe = s; end if;
            end if;
            result.@add(new [pid: pid, exe: exe]);
          end if;
        end if;
      end loop;
      _dirClose(d);
    end if;
  end fun;

  fun SearchMem(pid, re, size, all)
    if all then
      result = new [];
    end if;

    if size = nil then
      size = 64; // 64MB
    end if;
    size *= MB;

    // Regions come from /proc/<pid>/maps, data from /proc/<pid>/mem. Addresses
    // are parsed with libc strtoull (Fun has no 64-bit literals/arithmetic);
    // they are only ever carried as values, never as literals.
    var maps = _readFile('/proc/' & pid & '/maps', 1024 * 1024);
    if maps = '' then exit; end if;
    var fd = _open('/proc/' & pid & '/mem', 0, 0);
    if fd < 0 then exit; end if;
    var chunk = 64 * 1024;
    var buf = ' '.x(chunk);
    var prev = '';
    for ln in split(/\n/, maps) do
      var m = ln.match(/^([0-9a-f]++)-([0-9a-f]++)\s([rwx-]++)/);
      if m and m.@(3).subpos('w') >= 0 then
        var a = _strtoull(m.@(1), 0, 16);
        var b = _strtoull(m.@(2), 0, 16);
        var cur = a;
        while cur < b do
          var n = b - cur;
          if n > chunk then
            n = chunk;
          end if;
          var got = _pread(fd, buf.toNum(-1), n, cur);
          if got <= 0 then
            exit;
          end if;
          var s = prev & buf.substr(0, got);
          var mm = s.match(re);
          if mm then
            if all then
              result.@add(mm.@@());
            else
              _close(fd);
              return mm;
            end if;
          end if;
          prev = s.substr(-1024);
          cur += got;
        end do;
      end if;
    end do;
    _close(fd);
  end fun;
end class;
