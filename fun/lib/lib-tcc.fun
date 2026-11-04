// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// Tiny C Compiler backend, resolved by name at load time. Windows ships
// libtcc.dll next to fun.exe; on Linux the build produces libtcc.so from
// src/3rd/tcc and places it next to funcmd, and funcmd is linked with
// -rpath $ORIGIN so the bare name resolves (see art/notes/library-port-plan.md).
// macOS would need libtcc.dylib (cross-built with Zig; not produced yet), so
// `tcc` stays nil there and the JIT C path raises.
var tccdll = 'libtcc.dll';
var _tccos = 'host'.arg().getJson(fd: true).os;
if _tccos = 'linux' then
  tccdll = 'libtcc.so';
elsif _tccos = 'macos' then
  tccdll = 'libtcc.dylib';
end if;

// Prefer the copy next to the executable. Newer linkers emit DT_RUNPATH for
// -rpath, and dlopen() does not consult the executable's RUNPATH, so the bare
// name alone fails on Ubuntu 24.04 even though libtcc.so is beside the binary.
var tccpath = tccdll;
if _tccos = 'linux' then
  var exedir = 0.arg().replace(%[^/]*$%, '');
  if exedir <> '' then tccpath = exedir & tccdll; end if;
end if;

fun _tccLoad(name)
  result = [
    New:     name.getapi('tcc_new',            'v:i' ),
    Delete:  name.getapi('tcc_delete',         'i:v' ),
    Error:   name.getapi('tcc_set_error_func', 'iic:v'),
    Options: name.getapi('tcc_set_options',    'is:i'),
    Compile: name.getapi('tcc_compile_string', 'is:i'),
    Reloc:   name.getapi('tcc_relocate',       'ii:i'), // 1
    Get:     name.getapi('tcc_get_symbol',     'is:i'),
  ];
end fun;

var tcc = nil;
var tcc_error = nil;
try
  fun error(p, m)
    ?. m;
  end fun;
  tcc_error = error.@toCallback(nil, 'is:C');

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
