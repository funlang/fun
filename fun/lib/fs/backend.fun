// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fs/backend: platform directory primitives. Internal to fs.fun.
use '../lib-host.fun';

var _fsWin = IsWindows();
var _fsMac = IsMac();
var _fsBits = 'host'.arg().getJson(fd: true).bits;
var _fsChars = 'host'.arg().getJson(fd: true).chars;
var _fsAttrDir = 16;
var _fsAttrReparse = 1024;
var _fsAccess;
var _fsOpendir;
var _fsReaddir;
var _fsClosedir;
var _fsReadlink;
var _fsMemcpy;
var _fsMkdirU;
var _fsChmodU;
var _fsRmdirU;
var _fsUnlinkU;
var _fsRenameU;
var _fsAttrsA;
var _fsAttrsW;
var _fsMkdirA;
var _fsMkdirW;
var _fsRmdirA;
var _fsRmdirW;
var _fsUnlinkA;
var _fsUnlinkW;
var _fsRenameA;
var _fsRenameW;

if _fsWin then
  _fsAttrsA  = 'kernel32'.getapi('GetFileAttributesA', 's:i');
  _fsAttrsW  = 'kernel32'.getapi('GetFileAttributesW', 's:i');
  _fsMkdirA  = 'kernel32'.getapi('CreateDirectoryA', 'sp:i');
  _fsMkdirW  = 'kernel32'.getapi('CreateDirectoryW', 'sp:i');
  _fsRmdirA  = 'kernel32'.getapi('RemoveDirectoryA', 's:i');
  _fsRmdirW  = 'kernel32'.getapi('RemoveDirectoryW', 's:i');
  _fsUnlinkA = 'kernel32'.getapi('DeleteFileA', 's:i');
  _fsUnlinkW = 'kernel32'.getapi('DeleteFileW', 's:i');
  _fsRenameA = 'kernel32'.getapi('MoveFileExA', 'ssi:i');
  _fsRenameW = 'kernel32'.getapi('MoveFileExW', 'ssi:i');
else
  _fsAccess   = LibC().getapi('access', 'si:i');
  _fsOpendir  = LibC().getapi('opendir', 's:p');
  if _fsMac then
    // x86_64's plain readdir is the legacy 32-bit-inode layout; arm64 ships
    // only the 64-bit variant and has no $INODE64 alias
    try
      _fsReaddir = LibC().getapi('readdir$INODE64', 'p:p');
    except
      _fsReaddir = LibC().getapi('readdir', 'p:p');
    end try;
  else
    _fsReaddir = LibC().getapi('readdir', 'p:p');
  end if;
  _fsClosedir = LibC().getapi('closedir', 'p:i');
  _fsReadlink = LibC().getapi('readlink', 'spi:i');
  _fsMemcpy   = LibC().getapi('memcpy', 'ppn:p');
  _fsMkdirU   = LibC().getapi('mkdir', 'si:i');
  _fsChmodU   = LibC().getapi('chmod', 'si:i');
  _fsRmdirU   = LibC().getapi('rmdir', 's:i');
  _fsUnlinkU  = LibC().getapi('unlink', 's:i');
  _fsRenameU  = LibC().getapi('rename', 'ss:i');
end if;

fun _fsNative(p)
  if _fsWin then result = ('' & p).replace('/', 92.toChar()); else result = p; end if;
end fun;

fun _fsWinAttrs(q)
  if _fsChars = 2 then result = _fsAttrsW(q); else result = _fsAttrsA(q); end if;
end fun;

fun _fsExists(p)
  if p = nil or p = '' then result = false; return; end if;
  var q = _fsNative(p);
  if _fsWin then result = _fsWinAttrs(q) >= 0;
  else result = _fsAccess(q, 0) = 0; end if;
end fun;

fun _fsIsDir(p)
  if p = nil or p = '' then result = false; return; end if;
  var q = _fsNative(p);
  if _fsWin then
    var a = _fsWinAttrs(q);
    result = a >= 0 and (a bit and _fsAttrDir) <> 0;
  else
    var d = _fsOpendir(q);
    if d = nil then result = false; return; end if;
    _fsClosedir(d);
    result = true;
  end if;
end fun;

// symlink or Windows reparse point; walk/removeAll must not follow it
fun _fsIsLink(p)
  if p = nil or p = '' then result = false; return; end if;
  var q = _fsNative(p);
  if _fsWin then
    var a = _fsWinAttrs(q);
    result = a >= 0 and (a bit and _fsAttrReparse) <> 0;
  else
    var b = 0.toChar().x(1);
    result = _fsReadlink(q, b.toNum(-1), 1) >= 0;
  end if;
end fun;

// delete the link itself, never the target
fun _fsRemoveLink(p)
  var q = _fsNative(p);
  if _fsWin then
    var a = _fsWinAttrs(q);
    if a >= 0 and (a bit and _fsAttrDir) <> 0 then
      if _fsChars = 2 then result = _fsRmdirW(q) <> 0; else result = _fsRmdirA(q) <> 0; end if;
    else
      if _fsChars = 2 then result = _fsUnlinkW(q) <> 0; else result = _fsUnlinkA(q) <> 0; end if;
    end if;
  else
    result = _fsUnlinkU(q) = 0;
  end if;
end fun;

// NUL-terminated name inside a byte buffer, at off, at most maxLen bytes
fun _fsCStr(b, off, maxLen)
  var n = 0;
  while n < maxLen and b.toByte(off + n) <> 0 do n += 1; end do;
  result = b.substr(off, n);
end fun;

// raw entry names on byte-char 64-bit POSIX (includes broken links); else nil
fun _fsDirNames(dir)
  result = nil;
  if _fsWin or _fsBits <> 64 or _fsChars <> 1 then return; end if;
  var dp = _fsOpendir(_fsNative(dir));
  if dp = nil then result = new []; return; end if;
  result = new [];
  // struct dirent (64-bit): d_name at 21 on Darwin (d_namlen@18, d_type@20),
  // at 19 on Linux (d_type@18); d_reclen@16 on both.
  var noff = 19;
  if _fsMac then noff = 21; end if;
  var de = _fsReaddir(dp);
  while de <> 0 do
    var hd = 0.toChar().x(24);
    _fsMemcpy(hd.toNum(-1), de, 24);
    var reclen = hd.toByte(16) bit or (hd.toByte(17) << 8);
    if reclen > noff and reclen < 2048 then
      var b = 0.toChar().x(2048);
      _fsMemcpy(b.toNum(-1), de, reclen);
      var nm = _fsCStr(b, noff, reclen - noff);
      if nm <> '.' and nm <> '..' then result.@add(nm); end if;
    end if;
    de = _fsReaddir(dp);
  end do;
  _fsClosedir(dp);
end fun;

// atomic replace on the same filesystem; returns the OS result.
// Windows flag 1 = MOVEFILE_REPLACE_EXISTING.
fun _fsRename(src, dst)
  var s = _fsNative(src);
  var d = _fsNative(dst);
  if _fsWin then
    if _fsChars = 2 then result = _fsRenameW(s, d, 1) <> 0;
    else result = _fsRenameA(s, d, 1) <> 0; end if;
  else
    result = _fsRenameU(s, d) = 0;
  end if;
end fun;

fun _fsChmod(p, mode)
  if _fsWin then result = true;
  else result = _fsChmodU(_fsNative(p), mode) = 0; end if;
end fun;

fun _fsMkdirMode(p, mode)
  var q = _fsNative(p);
  if _fsWin then
    if _fsChars = 2 then result = _fsMkdirW(q, nil) <> 0;
    else result = _fsMkdirA(q, nil) <> 0; end if;
  else
    result = _fsMkdirU(q, mode) = 0;
  end if;
end fun;

fun _fsMkdir(p)
  result = _fsMkdirMode(p, 511);
end fun;

fun _fsRmdir(p)
  var q = _fsNative(p);
  if _fsWin then
    if _fsChars = 2 then result = _fsRmdirW(q) <> 0;
    else result = _fsRmdirA(q) <> 0; end if;
  else
    result = _fsRmdirU(q) = 0;
  end if;
end fun;

fun _fsUnlink(p)
  var q = _fsNative(p);
  if _fsWin then
    if _fsChars = 2 then result = _fsUnlinkW(q) <> 0;
    else result = _fsUnlinkA(q) <> 0; end if;
  else
    result = _fsUnlinkU(q) = 0;
  end if;
end fun;
