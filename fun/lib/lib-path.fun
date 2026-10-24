// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-path: lexical path helpers with host path semantics.
//
//     PathJoin(['src', 'main.fun'])       // src/main.fun, src\main.fun on Windows
//     PathClean('a/./b/../c')             // a/c
//     PathToSlash(nativePath)              // internal/URL path (always '/')
//     PathFromSlash('a/b')                // native path at an OS boundary
//
// Output uses HostSep(). Windows accepts both '/' and '\'; POSIX treats only
// '/' as a separator, so '\' stays a normal filename character. PathJoin takes
// a component array because Fun has no variadic calls; empty components are
// skipped. The helpers are lexical: they do not touch the filesystem.
use 'lib-host.fun';

var _pathSep = HostSep();
var _pathWin = IsWindows();
var _pathBackslash = 92.toChar();

fun _pathIsAlpha(c)
  result = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'.subpos(c) >= 0;
end fun;

// Convert '/' to the host separator; native '\' is left alone on Windows.
fun _pathNative(p)
  if _pathWin then
    result = p.replace('/', _pathSep);
  else
    result = p;
  end if;
end fun;

fun _pathIsSep(c)
  if c = '/' then result = true; return; end if;
  if _pathWin and c = _pathBackslash then result = true; return; end if;
  result = false;
end fun;

// Split a native path into a volume prefix (drive / UNC / root) and its body.
// A UNC volume keeps its trailing separator so it is treated as a root.
fun _pathVolume(p)
  result = '';
  if _pathWin then
    if p.length() >= 2 and p.substr(1, 1) = ':' and _pathIsAlpha(p.substr(0, 1)) then
      result = p.substr(0, 2);
      if p.length() >= 3 and _pathIsSep(p.substr(2, 1)) then
        result &= _pathSep;
      end if;
      return;
    end if;
    if p.length() >= 2 and p.substr(0, 2) = _pathBackslash & _pathBackslash then
      var rest = p.substr(2);
      if rest = '' then
        result = _pathBackslash & _pathBackslash;
        return;
      end if;
      var i = rest.subpos(_pathBackslash);
      if i < 0 then
        result = _pathBackslash & _pathBackslash & rest & _pathBackslash;
        return;
      end if;
      var server = rest.substr(0, i);
      var rest2 = rest.substr(i + 1);
      if rest2 = '' then
        result = _pathBackslash & _pathBackslash & server & _pathBackslash;
        return;
      end if;
      var j = rest2.subpos(_pathBackslash);
      if j < 0 then
        result = _pathBackslash & _pathBackslash & server & _pathBackslash & rest2 & _pathBackslash;
      else
        result = _pathBackslash & _pathBackslash & server & _pathBackslash & rest2.substr(0, j) & _pathBackslash;
      end if;
      return;
    end if;
    if p.length() >= 1 and p.substr(0, 1) = _pathBackslash then
      result = _pathBackslash;
      return;
    end if;
  elsif p.length() >= 1 and p.substr(0, 1) = '/' then
    result = '/';
  end if;
end fun;

// Lexically clean a path: collapse separators and '.', resolve '..'.
fun PathClean(p)
  if p = nil or p = '' then result = '.'; return; end if;
  var s = _pathNative('' & p);
  var vol = _pathVolume(s);
  var rooted = false;
  if vol <> '' then
    rooted = _pathIsSep(vol.substr(vol.length() - 1, 1));
  end if;
  var rest = s.substr(vol.length());
  while rest.length() > 0 and _pathIsSep(rest.substr(0, 1)) do
    rest = rest.substr(1);
  end do;

  var parts = new [];
  var cur = '';
  var i = 0;
  while i <= rest.length() do
    var ch = '';
    if i < rest.length() then ch = rest.substr(i, 1); end if;
    if i = rest.length() or _pathIsSep(ch) then
      if cur = '..' then
        if parts.@count() > 0 and parts[parts.@count() - 1] <> '..' then
          parts.@count(-1);
        elsif not rooted then
          parts.@add('..');
        end if;
      elsif cur <> '' and cur <> '.' then
        parts.@add(cur);
      end if;
      cur = '';
    else
      cur &= ch;
    end if;
    i += 1;
  end do;

  var out = '';
  for j = 0 to parts.@count() - 1 do
    if out <> '' then out &= _pathSep; end if;
    out &= parts[j];
  end do;

  if vol = '' then
    if out = '' then result = '.'; else result = out; end if;
  elsif rooted then
    result = vol & out;
  else
    if out = '' then result = vol & '.'; else result = vol & out; end if;
  end if;
end fun;

// Join components with the host separator, then clean the result.
// Empty and nil components are skipped.
fun PathJoin(parts)
  result = '';
  if parts = nil then return; end if;
  var s = '';
  for i = 0 to parts.@count() - 1 do
    var p = parts[i];
    if p <> nil then
      p = '' & p;
      if p <> '' then
        if s <> '' and not _pathIsSep(s.substr(s.length() - 1, 1)) and
           not _pathIsSep(p.substr(0, 1)) then
          s &= _pathSep;
        end if;
        s &= p;
      end if;
    end if;
  end do;
  if s <> '' then result = PathClean(s); end if;
end fun;

// Directory part, following Go path/filepath.Dir.
fun PathDir(p)
  if p = nil or p = '' then result = '.'; return; end if;
  var s = _pathNative('' & p);
  var vol = _pathVolume(s);
  if vol.length() > s.length() then
    result = vol.substr(0, vol.length() - 1);
    return;
  end if;
  var i = s.length() - 1;
  while i >= vol.length() and not _pathIsSep(s.substr(i, 1)) do i -= 1; end do;
  var dir = PathClean(s.substr(vol.length(), i - vol.length() + 1));
  result = PathClean(vol & dir);
end fun;

// Last element, following Go path/filepath.Base.
fun PathBase(p)
  if p = nil or p = '' then result = '.'; return; end if;
  var s = _pathNative('' & p);
  var e = s.length();
  while e > 0 and _pathIsSep(s.substr(e - 1, 1)) do e -= 1; end do;
  s = s.substr(0, e);
  var vol = _pathVolume(s);
  if vol.length() >= s.length() then
    result = _pathSep;
    return;
  end if;
  s = s.substr(vol.length());
  var i = s.length() - 1;
  while i >= 0 and not _pathIsSep(s.substr(i, 1)) do i -= 1; end do;
  result = s.substr(i + 1);
end fun;

// Extension of the last element, including the dot. ".bashrc" has extension
// ".bashrc"; a name with no dot has an empty extension.
fun PathExt(p)
  var b = PathBase(p);
  var dot = -1;
  var i = 0;
  while i < b.length() do
    if b.substr(i, 1) = '.' then dot = i; end if;
    i += 1;
  end do;
  if dot < 0 then result = ''; else result = b.substr(dot); end if;
end fun;

// True for '/...' on POSIX, a drive root or UNC path on Windows.
// A Windows root-relative '\foo' is not absolute (same as Go).
fun PathIsAbs(p)
  if p = nil or p = '' then result = false; return; end if;
  var s = _pathNative('' & p);
  if _pathWin then
    if s.length() >= 2 and s.substr(0, 2) = _pathBackslash & _pathBackslash then
      result = true;
    elsif s.length() >= 3 and s.substr(1, 1) = ':' and _pathIsAlpha(s.substr(0, 1)) and
          _pathIsSep(s.substr(2, 1)) then
      result = true;
    else
      result = false;
    end if;
  else
    result = s.substr(0, 1) = '/';
  end if;
end fun;

// Convert every '\' to '/', for internal paths and URLs.
fun PathToSlash(p)
  if p = nil then result = ''; return; end if;
  result = ('' & p).replace(_pathBackslash, '/');
end fun;

// Convert '/' to the host separator at a filesystem/FFI boundary.
fun PathFromSlash(p)
  if p = nil then result = ''; return; end if;
  if _pathWin then
    result = ('' & p).replace('/', _pathSep);
  else
    result = p;
  end if;
end fun;
