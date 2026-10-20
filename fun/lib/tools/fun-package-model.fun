// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-package-model: the shared read-only half of the package tools.
//
// It knows how to scan a manifest's dependencies set (Fun source, so strings
// and comments are skipped), how to name a source and where its cache entry
// lives. Editing commands and the run/pack launchers all use these helpers so
// they agree on names, cache paths and manifest syntax.
use '../lib-host.fun';
use 'fun-tool-util.fun';

fun trimDir(p)
  var t = p;
  if IsWindows() then t = t.replace(92.toChar(), '/'); end if;
  result = UtilTrimEnd(t);
end fun;

fun baseName(p)
  result = trimDir(p).replace(/^.*[\x2f]/, '');
end fun;

fun isTrim(c)
  result = c = ' ' or c = 9.toChar() or c = 10.toChar() or c = 13.toChar();
end fun;

fun isAlpha(c)
  result = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_'.subpos(c) >= 0;
end fun;

fun isIdent(c)
  result = isAlpha(c) or '0123456789'.subpos(c) >= 0;
end fun;

fun skipString(t, i, q)
  i += 1;
  while i < t.length() do
    if t.substr(i, 1) = q then
      if t.substr(i + 1, 1) = q then
        i += 2;   // '' inside a string is an escaped quote
      else
        result = i + 1;
        return;
      end if;
    else
      i += 1;
    end if;
  end do;
  result = i;
end fun;

fun skipLine(t, i)
  var n = t.substr(i).subpos(10.toChar());
  if n < 0 then result = t.length(); else result = i + n + 1; end if;
end fun;

// '#' to end of line, or '#* ... *#' across lines
fun skipComment(t, i)
  if t.substr(i + 1, 1) = '*' then
    var e = t.substr(i + 2).subpos('*#');
    if e < 0 then result = t.length(); else result = i + e + 4; end if;
  else
    result = skipLine(t, i);
  end if;
end fun;

// Fun's opAny token starts with '.' and may contain '#', '/', etc., so `.#`
// is an operator, not a comment. Scan past such a token before interpreting
// its characters. -1 means "not an opAny token here".
fun opChar(c)
  result = '~!#%^&*-+=\\|<>/?'.subpos(c) >= 0;
end fun;

fun opEnd(t, i)
  if t.substr(i, 1) <> '.' or not opChar(t.substr(i + 1, 1)) then
    result = -1;
    return;
  end if;
  var j = i + 1;
  while j < t.length() and opChar(t.substr(j, 1)) do j += 1; end do;
  result = j;
end fun;

fun trimText(s)
  var a = 0;
  var b = s.length();
  while a < b and isTrim(s.substr(a, 1)) do a += 1; end do;
  while b > a and isTrim(s.substr(b - 1, 1)) do b -= 1; end do;
  result = s.substr(a, b - a);
end fun;

fun findDepOpen(t)
  var i = 0;
  while i < t.length() do
    var c = t.substr(i, 1);
    var oe = opEnd(t, i);
    if oe >= 0 then
      i = oe;
    elsif c = '/' and t.substr(i + 1, 1) = '/' then
      i = skipLine(t, i);
    elsif c = '#' then
      i = skipComment(t, i);
    elsif c = "'" or c = '"' or c = '`' then
      i = skipString(t, i, c);
    elsif isAlpha(c) then
      var j = i;
      while j < t.length() do
        exit when not isIdent(t.substr(j, 1));
        j += 1;
      end do;
      if t.substr(i, j - i).lower() = 'dependencies' then
        var k = j;
        while k < t.length() and isTrim(t.substr(k, 1)) do k += 1; end do;
        if t.substr(k, 1) = ':' then
          k += 1;
          while k < t.length() and isTrim(t.substr(k, 1)) do k += 1; end do;
          if t.substr(k, 1) = '[' then result = k; return; end if;
          raise 'package: dependencies must be a set literal';
        end if;
      end if;
      i = j;
    else
      i += 1;
    end if;
  end do;
  result = -1;
end fun;

fun findBracketEnd(t, setAt)
  var depth = 0;
  var i = setAt;
  while i < t.length() do
    var c = t.substr(i, 1);
    var oe = opEnd(t, i);
    if oe >= 0 then
      i = oe;
    elsif c = '/' and t.substr(i + 1, 1) = '/' then
      i = skipLine(t, i);
    elsif c = '#' then
      i = skipComment(t, i);
    elsif c = "'" or c = '"' or c = '`' then
      i = skipString(t, i, c);
    else
      if c = '[' then depth += 1;
      elsif c = ']' then
        depth -= 1;
        if depth = 0 then result = i + 1; return; end if;
      end if;
      i += 1;
    end if;
  end do;
  result = -1;
end fun;

fun segKey(seg)
  var i = 0;
  while i < seg.length() do
    var c = seg.substr(i, 1);
    var oe = opEnd(seg, i);
    if oe >= 0 then
      i = oe;
    elsif c = '/' and seg.substr(i + 1, 1) = '/' then
      i = skipLine(seg, i);
    elsif c = '#' then
      i = skipComment(seg, i);
    elsif c = "'" or c = '"' or c = '`' then
      var e = skipString(seg, i, c);
      var key = seg.substr(i + 1, e - i - 2);
      var j = e;
      while j < seg.length() and isTrim(seg.substr(j, 1)) do j += 1; end do;
      if seg.substr(j, 1) = ':' then result = key; return; end if;
      i = e;
    else
      i += 1;
    end if;
  end do;
  result = '';
end fun;

fun parseEntries(inner)
  result = new [];
  var n = inner.length();
  var i = 0;
  var start = 0;
  var depth = 0;
  while i <= n do
    var c = '';
    if i < n then c = inner.substr(i, 1); end if;
    var oe = opEnd(inner, i);
    if oe >= 0 then
      i = oe;
    elsif (i = n) or ((c = ',') and (depth = 0)) then
      var seg = trimText(inner.substr(start, i - start));
      if seg <> '' then
        var key = segKey(seg);
        if key <> '' then result.@add(key & 31.toChar() & seg); end if;
      end if;
      start = i + 1;
      i += 1;
    elsif c = '/' and inner.substr(i + 1, 1) = '/' then
      i = skipLine(inner, i);
    elsif c = '#' then
      i = skipComment(inner, i);
    elsif c = "'" or c = '"' or c = '`' then
      i = skipString(inner, i, c);
    else
      if c = '[' or c = '(' or c = '{' then depth += 1;
      elsif c = ']' or c = ')' or c = '}' then depth -= 1; end if;
      i += 1;
    end if;
  end do;
end fun;

fun entryName(e)
  result = e.substr(0, e.subpos(31.toChar()));
end fun;

fun parentOf(p)
  var t = trimDir(p);
  var i = t.length() - 1;
  while i >= 0 do
    if t.substr(i, 1) = '/' then result = t.substr(0, i); return; end if;
    i -= 1;
  end do;
  result = '';
end fun;

fun sourceIsGit(s)
  if s.subpos('://') >= 0 then result = true; return; end if;
  if s.substr(0, 4) = 'git@' then result = true; return; end if;
  result = not not s.match(/^[A-Za-z0-9][A-Za-z0-9._-]*\.[A-Za-z0-9._-]+\x2f[^\x2f]+\x2f[^\x2f]+$/);
end fun;

fun sourceKey(s)
  var t = s;
  t = t.replace('https://', '').replace('http://', '').replace('ssh://', '').replace('git://', '');
  if t.substr(0, 4) = 'git@' then t = t.substr(4).replace(':', '/'); end if;
  if t.substr(0, 7) = 'file://' then t = 'file/' & t.substr(7); end if;
  if IsWindows() then t = t.replace(92.toChar(), '/'); end if;
  if t.length() > 4 and t.substr(t.length() - 4) = '.git' then t = t.substr(0, t.length() - 4); end if;
  var out = '';
  var i = 0;
  while i < t.length() do
    var c = t.substr(i, 1);
    if 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/'.subpos(c) >= 0 then
      out &= c;
    else
      out &= '-';
    end if;
    i += 1;
  end do;
  while out.substr(0, 1) = '/' do out = out.substr(1); end do;
  while out.subpos('//') >= 0 do out = out.replace('//', '/'); end do;
  if out = '' or out.subpos('..') >= 0 then
    raise 'package: cannot derive a cache path from source ' & s;
  end if;
  result = out;
end fun;

fun cacheDirFor(src, commit)
  result = UtilFunHome() & 'packages/' & sourceKey(src) & '@' & commit;
end fun;

fun readPkg(dir)
  var mp = trimDir(dir) & '/package.fun';
  if not UtilExists(mp) then raise 'package: package.fun not found in ' & trimDir(dir); end if;
  result = mp.compile().package();
end fun;

fun depNamesOf(dir)
  result = new [];
  var mp = trimDir(dir) & '/package.fun';
  if not UtilExists(mp) then return; end if;
  var text = mp.load();
  var at = findDepOpen(text);
  if at < 0 then return; end if;
  var en = findBracketEnd(text, at);
  if en < 0 then return; end if;
  var entries = parseEntries(text.substr(at + 1, en - at - 2));
  var i = 0;
  while i < entries.@count() do
    result.@add(entryName(entries[i]));
    i += 1;
  end do;
end fun;

fun readLib(dir, name)
  var m = readPkg(dir);
  var l = m.lib or '';
  if l = '' then raise "package: dependency '" & name & "' has no lib entry"; end if;
  if l.subpos('..') >= 0 or l.substr(0, 1) = '/' then
    raise "package: dependency '" & name & "' has an unsafe lib path: " & l;
  end if;
  var lp = trimDir(dir) & '/' & l;
  if not UtilExists(lp) then raise "package: dependency '" & name & "' lib not found: " & l; end if;
  result = l;
end fun;

// --- resolved dependency graph (read-only) -------------------------------
// run and pack both consume the block `fun package tidy` wrote. This walks it
// once and keeps the result in parallel arrays, so the two launchers cannot
// drift on name validation, cache lookup or conflict detection.
var PkgResNames = new [];
var PkgResSrc = new [];
var PkgResVer = new [];
var PkgResDirs = new [];
var PkgResLibs = new [];
var PkgResSeen = new [];
var PkgResRoot = nil;

fun pkgResolve(parentDir, m, name, tag, rejectQuote)
  if not name.match(/^[a-z][a-z0-9_-]*$/) then
    raise tag & ": invalid dependency name '" & name & "'";
  end if;
  var d = nil;
  if m.dependencies <> nil then d = m.dependencies[name]; end if;
  if d = nil then
    raise tag & ": dependency '" & name & "' is not declared in " & trimDir(parentDir);
  end if;
  var src = d.source or '';
  var ver = d.version or '';
  if src = '' then raise tag & ": dependency '" & name & "' has no source"; end if;
  var git = sourceIsGit(src);
  var eff = src;
  if not git then
    eff = HostFullPath(trimDir(parentDir) & '/' & src);
    if IsWindows() then eff = eff.replace(92.toChar(), '/'); end if;
  end if;
  var k = PkgResSeen[name];
  if k <> nil then
    var ki = k - 1;
    if PkgResSrc[ki] <> eff or PkgResVer[ki] <> ver then
      raise tag & ": version conflict for '" & name & "'";
    end if;
    return;
  end if;
  var r = nil;
  if PkgResRoot <> nil then r = PkgResRoot[name]; end if;
  if r = nil then
    raise tag & ": package '" & name & "' is not installed; run 'fun package tidy'";
  end if;
  if (r.source or '') <> eff or (r.version or '') <> ver then
    raise tag & ": package '" & name & "' changed since tidy; run 'fun package tidy'";
  end if;
  var dir = eff;
  if git then
    var commit = r.commit or '';
    if commit = '' then raise tag & ": resolved commit for '" & name & "' is missing"; end if;
    dir = cacheDirFor(src, commit);
  end if;
  if not UtilIsDir(dir) then
    raise tag & ": cache for '" & name & "' is missing; run 'fun package tidy'";
  end if;
  var lib = readLib(dir, name);
  var lp = trimDir(dir) & '/' & lib;
  if rejectQuote and lp.subpos("'") >= 0 then
    raise tag & ": dependency path cannot contain a quote";
  end if;
  var idx = PkgResNames.@count();
  PkgResNames.@add(name);
  PkgResSrc.@add(eff);
  PkgResVer.@add(ver);
  PkgResDirs.@add(dir);
  PkgResLibs.@add(lp);
  PkgResSeen[name] = idx + 1;

  var m2 = readPkg(dir);
  var names = depNamesOf(dir);
  var i = 0;
  while i < names.@count() do
    pkgResolve(dir, m2, names[i], tag, rejectQuote);
    i += 1;
  end do;
end fun;

fun pkgResGraph(m, rootDir, tag, rejectQuote)
  PkgResRoot = m.resolved;
  var names = depNamesOf(rootDir);
  var i = 0;
  while i < names.@count() do
    pkgResolve(rootDir, m, names[i], tag, rejectQuote);
    i += 1;
  end do;
end fun;
