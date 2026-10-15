// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// lib-proc (Darwin backend): process listing and memory scanning via libproc
// and the mach VM API.
//
// The macOS sibling of lib-proc.fun (the Windows implementation) and
// lib-proc-lnx.fun (Linux /proc). The public API is identical -
// `proc.ProcList(...)` / `proc.SearchMem(...)` - so macOS callers
// `use 'lib-proc-darwin.fun'`. (Not `-unx`: the shared-backend suffix means
// Linux + macOS; this file binds Darwin-only libraries and cannot load on
// Linux.)
//
// ProcList: proc_listpids(PROC_ALL_PIDS), proc_pidinfo(PROC_PIDT_SHORTBSDINFO)
// for the short name and proc_pidpath for the full path. proc_name() is not
// used: on current macOS it resolves the caller's own process only.
//
// SearchMem: walks the target task's VM regions with mach_vm_region and reads
// them with mach_vm_read_overwrite. The caller's own task port needs no
// privileges; task_for_pid() for a foreign pid generally needs root or the
// debugger entitlement, in which case the scan returns nil (the shape the
// Linux backend has when /proc/<pid>/mem cannot be opened).
//
// Fun has no 64-bit hex literals and toNum is 32-bit, so 64-bit values are
// carried as values and memory is read/written as little-endian byte buffers
// (see _read64 / _write64; strtoull parses the re-assembled text).

use 'lib-utils.fun';
use 'lib-host.fun';

var MB = 1024 ^ 2;

var _memcpy   = LibC().getapi('memcpy', 'ppn:p');
var _strtoull = LibC().getapi('strtoull', 'pii:l'); // pointer form: the buffer holds raw bytes, not text
var _getpid   = LibC().getapi('getpid', ':i');

var _listpids = 'libproc.dylib'.getapi('proc_listpids', 'iipi:i');
var _pidinfo  = 'libproc.dylib'.getapi('proc_pidinfo', 'iilpi:i');
var _pidpath  = 'libproc.dylib'.getapi('proc_pidpath', 'ipi:i');

var _task_self = 'libSystem.B.dylib'.getapi('task_self_trap', ':i');
var _task_of   = 'libSystem.B.dylib'.getapi('task_for_pid', 'iii:i');
var _vm_region = 'libSystem.B.dylib'.getapi('mach_vm_region', 'ippippp:i');
var _vm_read   = 'libSystem.B.dylib'.getapi('mach_vm_read_overwrite', 'illlp:i');
var _port_free = 'libSystem.B.dylib'.getapi('mach_port_deallocate', 'ii:i');

var PROC_ALL_PIDS = 1;
var PROC_PIDT_SHORTBSDINFO = 13;
var _PBSI_COMM = 16; // struct proc_bsdshortinfo.pbsi_comm offset (64-bit)
var VM_REGION_BASIC_INFO_64 = 9;
var VM_PROT_WRITE = 2;
var SMBI_COUNT = 10; // sizeof(vm_region_basic_info_64) / 4

// little-endian 4-byte hunk -> number (32-bit results only, see _read64)
fun _leword(hex8)
  result = ('0x' & hex8.substr(6,2) & hex8.substr(4,2)
                  & hex8.substr(2,2) & hex8.substr(0,2)).toNum();
end fun;

// 64-bit little-endian hex text (int2hex's byte order, eight bytes)
fun _hex64(int)
  result = '';
  var v = int;
  for i = 0 to 7 do
    var b = v mod 256;
    result &= Hexs[b >> 4] & Hexs[b bit and 0x0f];
    v = v div 256;
  end do;
end fun;

fun _write64(buf, v)
  var s = hex2str(_hex64(v));
  _memcpy(buf.toNum(-1), s.toNum(-1), 8);
end fun;

// 8 raw little-endian bytes -> big-endian hex text -> a space-filled buffer ->
// strtoull (toNum would truncate to 32 bits; the trailing spaces stop the
// parse at the end of the 18-character text).
fun _read64(buf)
  var h = str2hex(buf.substr(0, 8));
  var big = h.substr(14,2) & h.substr(12,2) & h.substr(10,2) & h.substr(8,2)
          & h.substr(6,2) & h.substr(4,2) & h.substr(2,2) & h.substr(0,2);
  var tb = ' '.x(20);
  ('0x' & big).move(tb.toNum(-1));
  result = _strtoull(tb.toNum(-1), 0, 16);
end fun;

fun _procName(pid)
  var b = 0.x(64);
  result = '';
  if _pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, b.toNum(-1), 64) = 64 then
    result = b.substr(_PBSI_COMM, 17).replace(/\x00.*$/, '');
  end if;
end fun;

fun _procPath(pid)
  var b = 0.x(4096);
  var n = _pidpath(pid, b.toNum(-1), 4096);
  if n > 0 then result = b.substr(0, n); else result = ''; end if;
end fun;

var proc = Proclass();
class Proclass()
  fun ProcList(fullPath, exeList, exeLike)
    result = new [];
    var need = _listpids(PROC_ALL_PIDS, 0, nil, 0);
    if need > 0 then
      var pb = 0.x(need + 64);
      var got = _listpids(PROC_ALL_PIDS, 0, pb.toNum(-1), need + 64);
      if got > 0 then
        var npids = got div 4;
        var hx = str2hex(pb.substr(0, got));
        for i = 0 to npids - 1 do
          var pid = _leword(hx.substr(i*8, 8));
          if pid > 0 then
            var exe = _procName(pid);
            // filter on the short name first, then replace with the full path
            if (exeList = nil or exe in exeList) and (exeLike = nil or exe =~ exeLike) then
              if fullPath then
                var s = _procPath(pid);
                if s <> '' then exe = s; end if;
              end if;
              result.@add(new [pid: pid, exe: exe]);
            end if;
          end if;
        end do;
      end if;
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

    // Our own task port is free; a foreign pid needs task_for_pid, which
    // fails without root / the debugger entitlement -> degrade to nil.
    var task = nil;
    if pid = _getpid() then
      task = _task_self();
    else
      var tb = 0.x(9);
      if _task_of(_task_self(), pid, tb.toNum(-1)) = 0 then
        task = _leword(str2hex(tb.substr(0,4)));
      end if;
    end if;
    if task = nil then exit; end if;

    var ab = 0.x(9);   // region address in/out
    var sb = 0.x(9);   // region size out
    var cb = 0.x(5);   // info count in/out
    var ob = 0.x(5);   // object name out
    var info = 0.x(48);
    var on = 0.x(9);   // read-over-write out size
    _write64(ab, 0);
    var ct = hex2str(int2hex(SMBI_COUNT));
    _memcpy(cb.toNum(-1), ct.toNum(-1), 4);

    var chunk = 64 * 1024;
    var buf = 0.x(chunk);
    var prev = '';
    loop
      var rc = _vm_region(task, ab.toNum(-1), sb.toNum(-1), VM_REGION_BASIC_INFO_64,
                          info.toNum(-1), cb.toNum(-1), ob.toNum(-1));
      exit when rc <> 0;
      var start = _read64(ab);
      var rgn = _read64(sb);
      _port_free(task, _leword(str2hex(ob.substr(0,4))));
      var prot = _leword(str2hex(info.substr(0,4)));
      if (prot bit and VM_PROT_WRITE) <> 0 then
        var cur = start;
        var fin = start + rgn;
        while cur < fin do
          var n = fin - cur;
          if n > chunk then n = chunk; end if;
          _write64(on, 0);
          var kr = _vm_read(task, cur, n, buf.toNum(-1), on.toNum(-1));
          exit when kr <> 0; // unreadable page: give up on this region
          var gotn = _read64(on);
          exit when gotn <= 0;
          var s = prev & buf.substr(0, gotn);
          var m = s.match(re);
          if m then
            if all then
              result.@add(m.@@());
            else
              return m;
            end if;
          end if;
          prev = s.substr(-1024);
          cur += gotn;
        end do;
      end if;
      _write64(ab, start + rgn);
    end loop;
  end fun;
end class;
