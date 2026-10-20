// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-package: the package command group.
//
//     fun package init [dir] [--bin|--lib]
//
// `init` writes package.fun (the manifest) and, when the target directory is
// new or empty, a small runnable template. A non-empty directory gets the
// manifest only, so existing files are never overwritten. Both flags may be
// combined; the default is --bin.
//
// The manifest is Fun code: package() returns a set. Only the block between
// the two "generated" comments is rewritten by `fun package tidy`.
use '../lib-host.fun';

var _nl = 10.toChar();
var _facts = 'host'.arg().getJson(fd: true);
var _isWin = IsWindows();
var _isMac = IsMac();
var _bs = 92.toChar();

fun trimDir(p)
  var t = p;
  if _isWin then t = t.replace(_bs, '/'); end if;
  while t.length() > 1 and t.substr(t.length() - 1) = '/' do
    t = t.substr(0, t.length() - 1);
  end do;
  result = t;
end fun;

fun baseName(p)
  var t = p;
  if _isWin then t = t.replace(_bs, '/'); end if;
  result = t.replace(/^.*[\x2f]/, '');
end fun;

// --- host file checks: WinAPI on Windows, libc dirent elsewhere -----------
var _opendir;
var _readdir;
var _closedir;
var _findFirst;
var _findNext;
var _findClose;
var _getAttrs;
var _memcpy;
if _isWin then
  _findFirst = 'kernel32'.getapi('FindFirstFileA', 'ap:l');
  _findNext  = 'kernel32'.getapi('FindNextFileA',  'ip:i');
  _findClose = 'kernel32'.getapi('FindClose',      'i:i');
  _getAttrs  = 'kernel32'.getapi('GetFileAttributesA', 'a:i');
else
  _opendir  = LibC().getapi('opendir',  's:p');
  if _isMac then
    // x86_64's plain readdir is the legacy 32-bit-inode layout; arm64 ships
    // only the 64-bit variant and has no $INODE64 alias
    try
      _readdir = LibC().getapi('readdir$INODE64', 'p:p');
    except
      _readdir = LibC().getapi('readdir', 'p:p');
    end try;
  else
    _readdir = LibC().getapi('readdir', 'p:p');
  end if;
  _closedir = LibC().getapi('closedir', 'p:i');
  _memcpy   = LibC().getapi('memcpy',   'ppn:p');
end if;

fun cstr(b, off, maxLen)
  var n = 0;
  while n < maxLen and b.toByte(off + n) <> 0 do n += 1; end do;
  result = b.substr(off, n);
end fun;

// entry names in dir; [] when dir cannot be opened
fun listDir(dir)
  result = new [];
  if _isWin then
    var pat = dir.replace('/', _bs);
    if pat <> '' and pat.substr(pat.length() - 1) <> _bs then pat &= _bs; end if;
    var data = 0.toChar().x(592);   // WIN32_FIND_DATAA, d_name at 44
    var h = _findFirst(pat & '*', data);
    if h <= 0 then return; end if;
    var more = true;
    while more do
      var nm = cstr(data, 44, 260);
      if nm <> '.' and nm <> '..' then result.@add(nm); end if;
      more = _findNext(h, data) <> 0;
    end do;
    _findClose(h);
  else
    var dp = _opendir(dir);
    if dp = nil then return; end if;
    // struct dirent (64-bit): d_name at 21 on Darwin, 19 on Linux
    var noff = 19;
    if _isMac then noff = 21; end if;
    var de = _readdir(dp);
    while de <> 0 do
      var hd = 0.toChar().x(24);
      _memcpy(hd.toNum(-1), de, 24);
      var reclen = hd.toByte(16) bit or (hd.toByte(17) << 8);
      if reclen > noff and reclen < 2048 then
        var b = 0.toChar().x(2048);
        _memcpy(b.toNum(-1), de, reclen);
        var nm = cstr(b, noff, reclen - noff);
        if nm <> '.' and nm <> '..' then result.@add(nm); end if;
      end if;
      de = _readdir(dp);
    end do;
    _closedir(dp);
  end if;
end fun;

fun isDir(p)
  result = false;
  var t = trimDir(p);
  if t = '' then return; end if;
  if _isWin then
    var a = _getAttrs(t.replace('/', _bs));
    result = a >= 0 and (a bit and 16) <> 0;   // FILE_ATTRIBUTE_DIRECTORY
  else
    var dp = _opendir(t);
    if dp <> nil then _closedir(dp); result = true; end if;
  end if;
end fun;

fun exists(p)
  result = false;
  if p = '' then return; end if;
  if _isWin then
    result = _getAttrs(p.replace('/', _bs)) >= 0;
  else
    try
      result = not not p.find();
    except
      result = false;
    end try;
  end if;
end fun;

fun isDirAbs(p)
  result = isDir(trimDir(p));
end fun;

fun hasEntries(absDir)
  var names = listDir(trimDir(absDir));
  var i = 0;
  while i < names.@count() do
    if names[i] <> '.git' then result = true; return; end if;
    i += 1;
  end do;
  result = false;
end fun;

fun pkgName(absDir)
  var n = baseName(absDir).lower();
  var out = '';
  var i = 0;
  while i < n.length() do
    var c = n.substr(i, 1);
    if c.match(/^[a-z0-9_-]$/) then out &= c; else out &= '-'; end if;
    i += 1;
  end do;
  while out.subpos('--') >= 0 do out = out.replace('--', '-'); end do;
  if out = '' then
    result = 'package';
  elsif out.substr(0, 1).match(/^[a-z]$/) then
    result = out;
  else
    result = 'pkg-' & out;
  end if;
end fun;

fun writeFile(p, text)
  try
    p.save(text);
  except
    raise 'init: cannot write ' & p;
  end try;
end fun;

fun usage()
  ?. 'usage: fun package init [dir] [--bin|--lib]';
  ?. '';
  ?. '  init [dir]  create package.fun (default: .)';
  ?. '  --bin       add src/main.fun (default)';
  ?. '  --lib       add src/lib.fun';
end fun;

fun manifestText(pkg, binPath, libPath)
  result =
    "// package.fun - Fun package manifest; edit it, then run 'fun package tidy'." & _nl &
    'fun package()' & _nl &
    '  result = [' & _nl &
    "    name: '" & pkg & "'," & _nl &
    "    version: '0.1.0'," & _nl &
    "    bin: '" & binPath & "'," & _nl &
    "    lib: '" & libPath & "'," & _nl &
    "    'fun': '" & _facts['fun'] & "'," & _nl &
    '    dependencies: [],' & _nl &
    "    // >>> generated - do not edit; run 'fun package tidy' to refresh" & _nl &
    '    resolved: []' & _nl &
    '    // <<< generated' & _nl &
    '  ];' & _nl &
    'end fun;' & _nl;
end fun;

fun mainText(pkg)
  result =
    '// ' & pkg & ' - entry script' & _nl &
    'var who = 2.arg();' & _nl &
    "if who = '' then who = 'world'; end if;" & _nl &
    "?. 'hello, ' & who;" & _nl;
end fun;

fun libText(pkg)
  result =
    '// ' & pkg & ' - library entry' & _nl &
    'fun greeting(who)' & _nl &
    "  result = 'hello, ' & who;" & _nl &
    'end fun;' & _nl;
end fun;

fun bothMainText(pkg)
  result =
    '// ' & pkg & ' - entry script' & _nl &
    "use 'lib.fun';" & _nl &
    "?. greeting('world');" & _nl;
end fun;

fun readmeText(pkg)
  result =
    '# ' & pkg & _nl & _nl &
    'A Fun package.' & _nl & _nl &
    '    fun run' & _nl;
end fun;

fun cmdInit()
  var dirArg = '';
  var wantBin = false;
  var wantLib = false;
  var ai = 3;
  while ai.arg() <> '' do
    var a = ai.arg();
    if a = '--bin' then
      wantBin = true;
    elsif a = '--lib' then
      wantLib = true;
    elsif a = '-h' or a = '--help' then
      usage(); return;
    elsif a.substr(0, 1) = '-' then
      raise "init: unknown option '" & a & "'";
    elsif dirArg = '' then
      dirArg = a;
    else
      raise "init: unexpected argument '" & a & "'";
    end if;
    ai += 1;
  end do;
  if dirArg = '' then dirArg = '.'; end if;
  if not wantBin and not wantLib then wantBin = true; end if;

  var target = trimDir(HostFullPath(dirArg));
  var existing = isDirAbs(target);
  if not existing and exists(target) then
    raise 'init: not a directory: ' & target;
  end if;
  var manifest = target & '/package.fun';
  if exists(manifest) then
    raise 'init: package.fun already exists in ' & target;
  end if;

  var blank = true;
  if existing then blank = not hasEntries(target); end if;
  var pkg = pkgName(target);
  var binPath = '';
  var libPath = '';
  if blank then
    if wantBin then binPath = 'src/main.fun'; end if;
    if wantLib then libPath = 'src/lib.fun'; end if;
    if wantBin and wantLib then
      writeFile(target & '/src/main.fun', bothMainText(pkg));
      writeFile(target & '/src/lib.fun', libText(pkg));
    elsif wantBin then
      writeFile(target & '/src/main.fun', mainText(pkg));
    else
      writeFile(target & '/src/lib.fun', libText(pkg));
    end if;
    writeFile(target & '/.gitignore', 'dist/' & _nl & '*.log' & _nl);
    writeFile(target & '/README.md', readmeText(pkg));
  end if;
  writeFile(manifest, manifestText(pkg, binPath, libPath));

  if blank then
    ?. "initialized package '" & pkg & "' in " & target;
  else
    ?. "initialized package '" & pkg & "' in " & target & ' (kept existing files; no templates written)';
  end if;
end fun;

var cmd = 2.arg();
if cmd = 'init' then
  cmdInit();
elsif cmd = '' or cmd = '-h' or cmd = '--help' then
  usage();
else
  raise "package: unknown command '" & cmd & "'";
end if;
