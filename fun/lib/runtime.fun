// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// runtime: source locations, call stacks and the last caught error.
//
//     use 'runtime.fun';
//
//     runtime.source();       // [file, path, line, function, className]
//     runtime.stack();        // innermost-first frames
//     runtime.lastError();    // message + error point + stack
//     runtime.root('/app');  // short-path root, default is the startup cwd
//
// file is absolute; path is relative to root and is nil for an unknown file.
use 'lib-host.fun';
use 'lib-path.fun';

var _runtimeInitRoot = PathClean(HostCurrPath());
var _runtimeRoot = nil;

fun _runtimeBase()
  if _runtimeRoot = nil then result = _runtimeInitRoot; else result = _runtimeRoot; end if;
end fun;

fun _runtimeShort(file)
  if file = nil or file = '' then result = nil; return; end if;
  result = PathRel(_runtimeBase(), file);
  if result = nil then result = file; end if;
end fun;

fun _runtimeAddPath(frame)
  if frame = nil then return; end if;
  frame['path'] = _runtimeShort(frame['file']);
end fun;

class _RuntimeApi()
  fun source(depth)
    if depth = nil then depth = 0; end if;
    var s = ''.__source(depth);
    if s = nil then result = nil; return; end if;
    _runtimeAddPath(s);
    result = s;
  end fun;

  fun stack(max)
    // `0 = nil` is true in Fun, so use the type id to keep max=0 meaningful.
    if max.type() = 0 then max = 32; end if;
    var ls = ''.__stack(max);
    if ls = nil then result = []; return; end if;
    if ls.@count() > 0 then
      for i = 0 to ls.@count() - 1 do
        _runtimeAddPath(ls[i]);
      end do;
    end if;
    result = ls;
  end fun;

  fun lastError()
    var e = ''.__lastError();
    if e = nil then result = nil; return; end if;
    _runtimeAddPath(e);
    var st = e['stack'];
    if st <> nil and st.@count() > 0 then
      for i = 0 to st.@count() - 1 do
        _runtimeAddPath(st[i]);
      end do;
    end if;
    result = e;
  end fun;

  fun root(path)
    // `0 = nil` and `'' = nil` are true in Fun; use the type id for the getter.
    if path.type() = 0 then result = _runtimeBase(); return; end if;
    var p = '' & path;
    if p = '' then
      _runtimeRoot = nil;
    else
      _runtimeRoot = PathClean(HostFullPath(p));
    end if;
    result = _runtimeBase();
  end fun;
end class;

var runtime = _RuntimeApi();
