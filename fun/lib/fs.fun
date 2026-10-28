// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fs: portable filesystem helpers for directories, temporary entries,
// atomic writes and byte-oriented file handles. Whole-file read/write and
// copy/move stay on the existing built-ins. walk/removeAll do not follow
// symbolic links.
//
//     use 'fs.fun';
//
//     fs.mkdirAll('build/out');
//     fs.list('build');
//     fs.walk('src', (p, isDir) { ... });   // depth-first, sorted per level
//     fs.removeAll('build');
//     var t = fs.tempFile('job-');
//     fs.atomicWrite('config.json', data);
//     var f = fs.open('data.bin', 'r+');
//     f.seek(16, 0); var head = f.read(4); f.close();
use 'lib-path.fun';
use 'lib-host.fun';
use 'uuid.fun';
use 'fs/backend.fun';
use 'fs/file.fun';

fun _fsCollect(paths, names, seen)
  for i = 0 to paths.@count() - 1 do
    var n = PathBase(paths[i]);
    if n <> '' and n <> '.' and n <> '..' and seen[n] = nil then
      seen[n] = true;
      names.@add(n);
    end if;
  end do;
end fun;

fun _fsListRaw(dir)
  result = new [];
  if dir = nil or dir = '' then return; end if;
  var base = PathClean(dir);
  if not _fsIsDir(base) then return; end if;
  var native = _fsDirNames(base);
  if native <> nil then
    result = native;
    return;
  end if;
  var seen = new [];
  var pat = PathJoin([base, '*']);
  _fsCollect(pat.find(), result, seen);
  _fsCollect((pat & HostSep()).find(), result, seen);
end fun;

fun _fsSort(xs)
  for i = 1 to xs.@count() - 1 do
    var x = xs[i];
    var j = i - 1;
    while j >= 0 and xs[j] > x do
      xs[j + 1] = xs[j];
      j -= 1;
    end do;
    xs[j + 1] = x;
  end do;
  result = xs;
end fun;

fun _fsSafePrefix(prefix)
  if prefix = nil or prefix = '' then result = 'fun-'; return; end if;
  if prefix.subpos('/') >= 0 or prefix.subpos(92.toChar()) >= 0 then
    result = 'fun-';
  else
    result = prefix;
  end if;
end fun;

fun _fsTempPath(prefix)
  var parts = new [];
  parts.@add(HostTempPath(''));
  parts.@add(_fsSafePrefix(prefix) & UUID());
  result = PathJoin(parts);
end fun;

fun _fsMkdirAll(p)
  if p = nil or p = '' then result = false; return; end if;
  var q = PathClean(p);
  if _fsIsDir(q) then result = true; return; end if;
  if _fsExists(q) then result = false; return; end if;
  var parent = PathDir(q);
  if parent <> q and parent <> '.' then
    if not _fsMkdirAll(parent) then result = false; return; end if;
  end if;
  if _fsMkdir(q) then result = true; else result = _fsIsDir(q); end if;
end fun;

fun _fsRemoveAll(p)
  if _fsIsLink(p) then result = _fsRemoveLink(p); return; end if;
  if not _fsExists(p) then result = true; return; end if;
  if _fsIsDir(p) then
    var names = _fsListRaw(p);
    for i = 0 to names.@count() - 1 do
      if not _fsRemoveAll(PathJoin([p, names[i]])) then result = false; return; end if;
    end do;
    result = _fsRmdir(p);
  else
    result = _fsUnlink(p);
  end if;
end fun;

fun _fsWalk(p, fn)
  var names = _fsSort(_fsListRaw(p));
  for i = 0 to names.@count() - 1 do
    var q = PathJoin([p, names[i]]);
    var d = false;
    if not _fsIsLink(q) then d = _fsIsDir(q); end if;
    if fn <> nil then fn(q, d); end if;
    if d then _fsWalk(q, fn); end if;
  end do;
end fun;

class _FsApi()
  fun exists(p)
    result = _fsExists(p);
  end fun;

  fun isDir(p)
    result = _fsIsDir(p);
  end fun;

  fun isFile(p)
    result = _fsExists(p) and not _fsIsDir(p);
  end fun;

  fun list(p)
    result = _fsSort(_fsListRaw(p));
  end fun;

  fun walk(p, fn)
    if p = nil or p = '' then result = false; return; end if;
    var q = PathClean(p);
    if _fsIsLink(q) then result = false; return; end if;
    if not _fsIsDir(q) then result = false; return; end if;
    _fsWalk(q, fn);
    result = true;
  end fun;

  fun mkdirAll(p)
    result = _fsMkdirAll(p);
  end fun;

  fun removeAll(p)
    if p = nil or p = '' then result = true; return; end if;
    result = _fsRemoveAll(PathClean(p));
  end fun;

  fun open(p, mode)
    result = _FsFile(p, mode);
  end fun;

  fun tempFile(prefix)
    var p = _fsTempPath(prefix);
    try
      p.save('', cp: 10056);
      if _fsChmod(p, 384) then result = p;   // 0600
      else _fsUnlink(p); result = nil; end if;
    except
      if _fsExists(p) then _fsUnlink(p); end if;
      result = nil;
    end try;
  end fun;

  fun tempDir(prefix)
    var p = _fsTempPath(prefix);
    if _fsMkdirMode(p, 448) then result = p;   // 0700
    else result = nil; end if;
  end fun;

  fun atomicWrite(p, data)
    if p = nil or p = '' then result = false; return; end if;
    var q = PathClean(p);
    if _fsIsDir(q) then result = false; return; end if;
    var dir = PathDir(q);
    if dir <> '.' and not _fsIsDir(dir) then
      if not _fsMkdirAll(dir) then result = false; return; end if;
    end if;
    var parts = new [];
    parts.@add(dir);
    parts.@add('.fun-' & UUID() & '.tmp');
    var tmp = PathJoin(parts);
    try
      tmp.save(data or '', cp: 10056);
    except
      if _fsExists(tmp) then _fsUnlink(tmp); end if;
      result = false;
      return;
    end try;
    result = _fsRename(tmp, q);
    if not result and _fsExists(tmp) then _fsUnlink(tmp); end if;
  end fun;
end class;

var fs = _FsApi();
