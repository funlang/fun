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
var _runtimePaths = new [];

fun _runtimeBase()
  if _runtimeRoot = nil then result = _runtimeInitRoot; else result = _runtimeRoot; end if;
end fun;

fun _runtimeShort(file)
  if file = nil or file = '' then result = nil; return; end if;
  // PathRel cleans both sides, so cache per file. Logging hits this on every
  // record; after the first call per file it is a single map lookup.
  var hit = _runtimePaths[file];
  if hit <> nil then result = hit; return; end if;
  var p = PathRel(_runtimeBase(), file);
  if p = nil then p = file; end if;
  _runtimePaths[file] = p;
  result = p;
end fun;

fun _runtimeAddPath(frame)
  if frame = nil then return; end if;
  frame['path'] = _runtimeShort(frame['file']);
end fun;

class _RuntimeApi()
  fun source(depth, mode)
    if depth = nil then depth = 0; end if;
    if mode = nil then mode = 1; end if;
    var s = 'runtime'.frame(depth, mode);
    if s = nil then result = nil; return; end if;
    _runtimeAddPath(s);
    result = s;
  end fun;

  fun stack(max)
    // `0 = nil` is true in Fun, so use the type id to keep max=0 meaningful.
    if max.type() = 0 then max = 32; end if;
    if max < 0 then raise 'runtime: max must be >= 0'; end if;
    var ls = new [];
    var n = 'runtime'.frame();
    // Index 0 is runtime.stack itself; the caller chain starts at 1.
    var i = 1;
    while i < n and ls.@count() < max do
      var fr = 'runtime'.frame(i, 2);
      if fr <> nil then
        _runtimeAddPath(fr);
        ls.@add(fr);
      end if;
      i += 1;
    end do;
    result = ls;
  end fun;

  fun lastError()
    var e = 'runtime'.lastError();
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
    _runtimePaths = new [];
    result = _runtimeBase();
  end fun;
end class;

var runtime = _RuntimeApi();
