// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// Tiny C Compiler backend, resolved by name at load time. Windows ships
// libtcc.dll next to fun.exe; on Linux the build produces libtcc.so from
// src/3rd/tcc and places it next to funcmd, and funcmd is linked with
// -rpath $ORIGIN so the bare name resolves (see art/notes/library-port-plan.md).
// macOS x86_64 builds libtcc.dylib from the same source and places it next to
// funcmd. Apple Silicon still lacks a Darwin arm64 TCC backend, so `tcc` stays
// nil there and the JIT C path raises.
var tccdll = 'libtcc.dll';
var _tccos = 'host'.arg().getJson(fd: true).os;
// 32-bit Windows still goes through the legacy winapi.pas getapi, which passes
// a 'p' argument as the address of the Fun value rather than the pointer it
// holds. There a pointer must travel as 'i': on that host an int and a pointer
// are both 32 bits, and 'i' passes the raw value. The 64-bit Windows libffi
// backend and the Unix ones take 'p' correctly, so only win32 rewrites.
var _tccWin32 = _tccos = 'windows' and 'host'.arg().getJson(fd: true).bits = 32;
if _tccos = 'linux' then
  tccdll = 'libtcc.so';
elsif _tccos = 'macos' then
  tccdll = 'libtcc.dylib';
end if;

// Prefer the copy next to the executable. Newer linkers emit DT_RUNPATH for
// -rpath, and dlopen() does not consult the executable's RUNPATH, so the bare
// name alone fails on Ubuntu 24.04 even though libtcc.so is beside the binary.
// macOS has the same problem: a bare dlopen() name does not search the
// executable's directory.
var tccpath = tccdll;
if _tccos = 'linux' or _tccos = 'macos' then
  var exedir = 0.arg().replace(%[^/]*$%, '');
  if exedir <> '' then tccpath = exedir & tccdll; end if;
end if;

// FFI signature for this host: 'p' everywhere except win32 (see above).
fun _tccSig(sig)
  if _tccWin32 then sig = sig.replace('p', 'i'); end if;
  result = sig;
end fun;

fun _tccLoad(name)
  result = [
    // TCCState* and symbol addresses are pointers. Use 'p' (full width) rather
    // than 'i' (signed 32-bit): Linux happens to place TCC's heap below 4GB,
    // but macOS returns addresses above it, so 'i' truncates the state and
    // every following call sees a bogus pointer. _tccSig() maps these back to
    // 'i' on 32-bit Windows, where 'p' itself is what is broken.
    New:     name.getapi('tcc_new',            _tccSig('v:p' )),
    Delete:  name.getapi('tcc_delete',         _tccSig('p:v' )),
    Error:   name.getapi('tcc_set_error_func', _tccSig('ppc:v')),
    Options: name.getapi('tcc_set_options',    _tccSig('ps:v')),
    Compile: name.getapi('tcc_compile_string', _tccSig('ps:i')),
    Reloc:   name.getapi('tcc_relocate',       _tccSig('pi:i')), // 1 = AUTO
    Get:     name.getapi('tcc_get_symbol',     _tccSig('ps:p')),
  ];
end fun;

var tcc = nil;
var tcc_error = nil;
try
  fun error(p, m)
    ?. m;
  end fun;
  tcc_error = error.@toCallback(nil, _tccSig('ps:C'));

  try
    tcc = _tccLoad(tccpath);
  except
    if tccpath <> tccdll then tcc = _tccLoad(tccdll); else ?. @; end if;
  end try;
except ?. @;
end try;

fun ccompile(code, flag, name)
  fun GetArgs(m)
    if flag = nil then
      flag = m.@(1);
    end if;
    result = '';
  end fun;

  result = nil;
  code = code.replace(/^#!c\b(?:[:=]?\s*+(\w*+:\w*+))?/i, m->GetArgs(m));
  name = name or code.match(/\w++(?=\s*+\()/).@@();
  code = 'void _start(){}' & code;

  var ts = tcc.New();             //?, 'ts';    ?. ts;
  tcc.Error(ts, 0, tcc_error); // cdecl
  tcc.Options(ts, "-nostdlib -nostdinc -O2");
  var i  = tcc.Compile(ts, code); //?, 'comp';  ?. i;
  exit when i = -1;

  i = tcc.Reloc(ts, 1);           //?, 'reloc'; ?. i;
  exit when i = -1;

  var ptr = tcc.Get(ts, name);    //?, 'get';   ?. ptr;
  result = nil.getapi(ptr, flag);

  //tcc.Delete(ts);
  result = new [call: result, del: -> tcc.Delete(ts)];
  result.Run    = result.call;
  result.Delete = result.del;
end fun;
