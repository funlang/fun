// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-pack: bundle a project into ONE executable -- the runtime (funcmd) with
// a zip payload and a 16-byte trailer ('FUNBUNDL' + payload size) appended.
// funcmd's UnpackBundle() extracts it to a temp directory at startup, chdirs
// there and runs the entry script, so the packaged app is a single file.
//
//     fun pack [entry.fun] -o <out>
//
// With package.fun in the cwd the entry defaults to the manifest bin and paths
// are project-relative; a manifest with dependencies is refused until
// dependency bundling lands.
//
// `fun pack` runs this tool through the interpreter; invoking it directly
// (funcmd <path-to>/fun-pack.fun ...) works too, from any working directory.
//
// The payload always holds the entry and its transitive `use` dependencies
// (located by scanning the sources). Resources and other data files are added
// explicitly with -a, which takes one file or a whole directory:
//
//     fun pack main.fun -o dist/app -a public -a assets/logo.png
//
// An added path must sit inside the project root (the entry's directory) and
// keeps its root-relative path, so `-a public` serves the same 'public/...'
// paths the script uses at development time. Dependencies outside the root
// (e.g. use 'fun/lib/lib-json.fun') keep their repository-relative path, and
// bare stdlib names (use 'lib-x.fun') are also placed at the payload root.
// Files embedded with `use ':file' as id` (parse-time embedding: templates,
// tables, syntax files) are bundled automatically, stdlib ones included.
// '.funpack/entry' records the entry path.
//
// At run time the process working directory is the extracted payload root, so
// relative reads behave as in development; relative *writes* land in the temp
// directory and are removed with it on exit. On Windows the output name gets an
// '.exe' suffix when missing, and the runtime support DLLs that ship next to
// funcmd (pcre3.dll is a static import; ffi.dll for getapi, ...) are copied
// into the output directory, so a Windows result is the exe plus those DLLs.
//
// Files that already carry a bundle trailer are skipped, so re-packing in the
// same directory does not swallow earlier builds.
//
// v0 limits: STORE (uncompressed) entries only; CRC fields are 0 (the bundled
// runtime does not check them, external unzip tools warn); `use` names must be
// plain string literals (computed/conditional uses are not scanned); '.git',
// '.DS_Store' and 'Thumbs.db' are not packed.
//
// The tool itself has no `use` imports, so it runs from any working directory;
// the project's own imports are resolved against this file's location.
var _bs = 92.toChar();   // a single backslash: '\\' is TWO characters in Fun
var _facts = 'host'.arg().getJson(fd: true);
var _isWin = _facts.os = 'windows';
var _isMac = _facts.os = 'macos';

fun LibC()
  if _isWin then result = 'msvcrt.dll';
  elsif _isMac then result = 'libSystem.B.dylib';
  else result = 'libc.so.6'; end if;
end fun;

// --- arguments -----------------------------------------------------------
// 1.arg() is this script, the first user argument is 2.arg()
var selfPath = 1.arg();

// A package.fun in the cwd supplies the default entry and the project root.
// Dependencies are not bundled yet; refusing is better than a broken bundle.
var pkg = nil;
var hasPkg = false;
try
  var probe = 'package.fun'.load();
  hasPkg = probe <> '';
except
  hasPkg = false;
end try;
if hasPkg then
  pkg = 'package.fun'.compile().package();
  if pkg.dependencies <> nil and pkg.dependencies.@count() > 0 then
    raise "pack: package '" & (pkg.name or '?') & "' declares dependencies; they are not bundled yet";
  end if;
end if;

var entry = 2.arg();
var ai = 2;
if entry <> '' and entry.substr(0, 1) <> '-' then
  ai = 3;
elsif hasPkg then
  entry = pkg.bin;
  if entry = nil or entry = '' then
    raise "pack: package '" & (pkg.name or '?') & "' has no bin entry";
  end if;
else
  raise 'usage: fun pack <entry.fun> [-o <out>] [-a <file-or-dir>]';
end if;
if _isWin then entry = entry.replace(_bs, '/'); end if;
if hasPkg and (entry.subpos('..') >= 0 or entry.match(/^([a-zA-Z]:|\x2f)/)) then
  raise 'pack: the entry must be relative to the package directory';
end if;

var outFile = '';
var adds = new [];   // -a paths, in command-line order
while ai.arg() <> '' do
  if ai.arg() = '-o' then
    outFile = (ai + 1).arg();
    if outFile = '' then raise '-o needs a value'; end if;
    if _isWin then outFile = outFile.replace(_bs, '/'); end if;
    ai += 2;
  elsif ai.arg() = '-a' then
    var av = (ai + 1).arg();
    if av = '' then raise '-a needs a value'; end if;
    if _isWin then av = av.replace(_bs, '/'); end if;
    adds.@add(av);
    ai += 2;
  else
    raise 'unknown argument: ' & ai.arg();
  end if;
end do;
if outFile = '' then
  outFile = entry.replace(/^.*[\x2f]/, '').replace(/\.\w+$/, '');
end if;
if _isWin then
  var ob = outFile.replace(/^.*[\x2f]/, '');
  if ob.length() < 4 or ob.substr(ob.length() - 4).lower() <> '.exe' then
    outFile &= '.exe';
  end if;
end if;

fun dirname(p)
  result = p.replace(/[^\x2f]*+$/, '');
end fun;

// d ends with '/': 'R/fun/lib/tools/' -> 'R/fun/lib/'
fun parentDir(d)
  result = dirname(d.substr(0, d.length() - 1));
end fun;

// fun-pack.fun lives in <repo>/fun/lib/tools: the repo dirs follow from it
if _isWin then selfPath = selfPath.replace(_bs, '/'); end if;
var toolsDir = dirname(selfPath);
var libDir   = parentDir(toolsDir);
var repoRoot = parentDir(parentDir(libDir));
var root     = '';
if not hasPkg then root = dirname(entry); end if;   // manifest: paths are already project-relative

// --- files ---------------------------------------------------------------
var seen  = new [];   // zip path -> true
var files = new [];   // [src: host path, zip: payload path]
var warns = new [];

fun exists(p)
  result = false;
  if p <> '' then
    var t = p;
    if _isWin then
      // find() proved unreliable for Windows paths; attributes are not
      result = _getAttrs(t.replace('/', _bs)) >= 0;
    else
      try
        result = not not t.find();
      except
        result = false;
      end try;
    end if;
  end if;
end fun;

fun addFile(src, zipPath)
  if seen[zipPath] <> nil then return; end if;
  seen[zipPath] = true;
  // new [] + field assignment, not a [src: ..] literal: object literals in a
  // function body are one shared instance, mutated on every call.
  var e = new [];
  e.src = src;
  e.zip = zipPath;
  files.@add(e);
end fun;

fun relFor(p)
  result = '';
  if root = '' then
    // entry was a bare name: walked paths come as './x', deps as absolute
    // (repo-relative) or as-is
    if p.substr(0, 2) = './' then
      result = p.substr(2);
    elsif repoRoot <> '' and p.substr(0, repoRoot.length()) = repoRoot then
      result = p.substr(repoRoot.length());
    else
      result = p;
    end if;
  elsif p.substr(0, root.length()) = root then
    result = p.substr(root.length());
  elsif repoRoot <> '' and p.substr(0, repoRoot.length()) = repoRoot then
    result = p.substr(repoRoot.length());
  elsif repoRoot = '' then
    result = p;
  else
    result = p.replace(/^.*[\x2f]/, '');
  end if;
  if result.substr(0, 2) = './' then result = result.substr(2); end if;
end fun;

// --- host directory listing (libc dirent / FindFirstFileA) ---------------
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
    // x86_64 libSystem's plain readdir is the legacy 32-bit-inode variant;
    // arm64 only ships the 64-bit layout (and no $INODE64 alias)
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

// NUL-terminated name inside a byte buffer, at off, at most maxLen bytes
fun cstr(b, off, maxLen)
  var n = 0;
  while n < maxLen and b.toByte(off + n) <> 0 do n += 1; end do;
  result = b.substr(off, n);
end fun;

// entry names in directory dir; [] when dir cannot be opened
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
    // struct dirent (64-bit): d_name at 21 on Darwin (d_namlen@18, d_type@20),
    // at 19 on Linux (d_type@17); d_reclen@16 on both.
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
  var t = p;
  if t.length() > 1 and t.substr(t.length() - 1) = '/' then
    t = t.substr(0, t.length() - 1);   // "dir/" is not accepted everywhere
  end if;
  if _isWin then
    var a = _getAttrs(t.replace('/', _bs));
    result = a >= 0 and (a bit and 16) <> 0;   // FILE_ATTRIBUTE_DIRECTORY
  else
    var dp = _opendir(t);
    if dp <> nil then _closedir(dp); result = true; end if;
  end if;
end fun;

// --- collect project tree + dependency graph -----------------------------
// the output file is skipped when it sits inside the project root (re-packing
// a previous build must not swallow it)
var outRel = '';
if outFile.substr(0, root.length()) = root then
  outRel = outFile.substr(root.length());
  if outRel.substr(0, 2) = './' then outRel = outRel.substr(2); end if;
end if;

fun walk(dir)
  var names = listDir(dir);
  var ni = 0;
  while ni < names.@count() do
    var nm = names[ni];
    ni += 1;
    if nm <> '.git' and nm <> '.DS_Store' and nm <> 'Thumbs.db' then
      var p = dir & nm;
      if isDir(p) then
        walk(p & '/');
      elsif relFor(p) <> outRel then
        addFile(p, relFor(p));
      end if;
    end if;
  end do;
end fun;

// Resolve one `use` name the way parse.pas does: on macOS/Linux try the host
// variants first ('-darwin'/'-lnx', then '-unx'), keeping the literal when no
// variant file exists.
// NOTE: plain statements on purpose - expressions inside an array literal are
// evaluated on the first call only, so a candidate array would go stale.
fun tryPaths(nm, importer)
  result = '';
  var t = dirname(importer) & nm;
  if result = '' and exists(t) then result = t; end if;
  t = root & nm;
  if result = '' and exists(t) then result = t; end if;
  t = repoRoot & nm;
  if result = '' and exists(t) then result = t; end if;
  t = libDir & nm;
  if result = '' and exists(t) then result = t; end if;
  if result = '' and exists(nm) then result = nm; end if;
end fun;

fun endsWith(s, tail)
  result = s.length() >= tail.length() and s.substr(s.length() - tail.length()) = tail;
end fun;

fun resolveUse(name, importer)
  result = '';
  if not _isWin and endsWith(name, '.fun') then
    var stem = name.replace(/\.fun$/, '');
    if _isMac then
      result = tryPaths(stem & '-darwin.fun', importer);
    else
      result = tryPaths(stem & '-lnx.fun', importer);
    end if;
    if result = '' then result = tryPaths(stem & '-unx.fun', importer); end if;
  end if;
  if result = '' then result = tryPaths(name, importer); end if;
end fun;

var noScan = new [];   // embedded data files must not be scanned as modules

// `use ':file' as id` embeds a file at parse time (templates, tables, syntax
// files). Bundle it where the parser will look it up: project-relative, or
// repo-relative for stdlib data; bare names also get a payload-root copy.
fun addEmbed(name, importer)
  if name.substr(0, 1) = '/' or name.substr(1, 1) = ':' then
    warns.@add('cannot bundle absolute path :' & name & ' (from ' & importer & ')');
    return;
  end if;
  var resolved = tryPaths(name, importer);
  if resolved = '' then
    warns.@add('cannot resolve :' & name & ' (from ' & importer & ')');
    return;
  end if;
  var zp = relFor(resolved);
  if zp = '' or zp.substr(0, 1) = '/' or zp.substr(0, 3) = '../' or zp.substr(1, 1) = ':' then
    warns.@add('cannot place :' & name & ' (' & resolved & ')');
    return;
  end if;
  noScan[resolved] = true;
  addFile(resolved, zp);
  if name.subpos('/') < 0 then
    addFile(resolved, resolved.replace(/^.*[\x2f]/, ''));
  end if;
end fun;

var scanned = new [];
fun scanFile(src)
  if scanned[src] <> nil or noScan[src] <> nil then return; end if;
  scanned[src] = true;
  if not endsWith(src, '.fun') then return; end if;
  var text = src.load();
  var i = 0;
  while i < text.length() do
    var k = text.substr(i).subpos("use '");
    if k < 0 then exit; end if;
    var st = i + k + 5;
    var en = text.substr(st).subpos("'");
    if en < 0 then exit; end if;
    var name = text.substr(st, en);
    i = st + en + 1;
    if name <> '' then
      if name.substr(0, 1) = ':' then
        addEmbed(name.substr(1), src);
      else
        var resolved = resolveUse(name, src);
        if resolved = '' then
          warns.@add('cannot resolve ' & name & ' (from ' & src & ')');
        else
          addFile(resolved, relFor(resolved));
          if name.subpos('/') < 0 then
            addFile(resolved, resolved.replace(/^.*[\x2f]/, ''));
          end if;
          scanFile(resolved);
        end if;
      end if;
    end if;
  end do;
end fun;

addFile(entry, entry.substr(root.length()));
var ai2 = 0;
while ai2 < adds.@count() do
  var ap = adds[ai2];
  ai2 += 1;
  if ap.substr(0, 2) = './' then ap = ap.substr(2); end if;
  if ap = '.' then
    var wd = root;
    if wd = '' then wd = './'; end if;
    walk(wd);
  else
    if hasPkg and (ap.match(/^([a-zA-Z]:|\x2f)/) or ap.subpos('..') >= 0) then
      raise '-a path must be inside the project directory: ' & ap;
    end if;
    if ap.substr(0, root.length()) <> root then
      raise '-a path must be inside the project root (' & root & '): ' & ap;
    end if;
    var ad = ap;
    if ad.substr(ad.length() - 1) <> '/' then ad &= '/'; end if;
    if isDir(ad) then walk(ad); else addFile(ap, relFor(ap)); end if;
  end if;
end do;
var fi = 0;
while fi < files.@count() do
  scanFile(files[fi].src);
  fi += 1;
end do;

// --- zip (STORE entries, little-endian fields) ----------------------------
fun le32(v)
  result = (v bit and 255).toChar() &
           ((v >> 8) bit and 255).toChar() &
           ((v >> 16) bit and 255).toChar() &
           ((v >> 24) bit and 255).toChar();
end fun;

fun le16(v)
  result = le32(v).substr(0, 2);
end fun;

fun le64(v)
  result = le32(v) & 0.toChar().x(4);   // payloads stay below 4 GiB
end fun;

var z = '';
var centrals = '';
var zipN = 0;
fun zipAdd(zipPath, data)
  var nl = zipPath.length();
  var sz = data.length();
  var off = z.length();
  zipN += 1;
  z &= le32(0x04034B50) & le16(20) & le16(0) & le16(0) & le16(0) & le16(0) &
       le32(0) & le32(sz) & le32(sz) & le16(nl) & le16(0) & zipPath & data;
  centrals &= le32(0x02014B50) & le16(20) & le16(20) & le16(0) & le16(0) &
              le16(0) & le16(0) & le32(0) & le32(sz) & le32(sz) &
              le16(nl) & le16(0) & le16(0) & le16(0) & le16(0) &
              le32(0) & le32(off) & zipPath;
end fun;

zipAdd('.funpack/entry', entry.substr(root.length()));
var zf = 0;
while zf < files.@count() do
  var data = files[zf].src.load(cp: 0xffff);
  var n = data.length();
  // an earlier build in the same tree: skip, do not nest bundles
  if n < 16 or data.substr(n - 16, 8) <> 'FUNBUNDL' then
    zipAdd(files[zf].zip, data);
  end if;
  zf += 1;
end do;
var cdOff = z.length();
var cdLen = centrals.length();
z &= centrals;
z &= le32(0x06054B50) & le16(0) & le16(0) &
     le16(zipN) & le16(zipN) &
     le32(cdLen) & le32(cdOff) & le16(0);

// --- one file out: runtime + payload + trailer ---------------------------
outFile.save(0.arg().load(cp: 0xffff), cp: 0xffff);
outFile.save(z, cp: 0xffff, append: true);
outFile.save('FUNBUNDL' & le64(z.length()), cp: 0xffff, append: true);
if not _isWin then
  try
    LibC().getapi('chmod', 'si:i')(outFile, 0x1ED);   // 0755
  except
  end try;
end if;

// Windows: the runtime links against support DLLs that must sit next to the
// executable (pcre3.dll is a static import, so the loader needs it at start),
// so copy the ones shipped next to funcmd into the output directory.
if _isWin then
  var exePath = 0.arg();
  exePath = exePath.replace(_bs, '/');
  var rtDir  = dirname(exePath);
  var outDir = dirname(outFile);
  var di = 0;
  var dlls = new [];
  dlls.@add('pcre3.dll');
  dlls.@add('ffi.dll');
  dlls.@add('libffi-8.dll');
  dlls.@add('zlib1.dll');
  dlls.@add('libtcc.dll');
  dlls.@add('tcc.dll');
  var copied = '';
  while di < dlls.@count() do
    var dsrc = rtDir & dlls[di];
    var data = '';
    try
      data = dsrc.load(cp: 0xffff);   // a present file; no exists()/find() here
    except
      data = '';
    end try;
    if data <> '' then
      (outDir & dlls[di]).save(data, cp: 0xffff);
      copied &= ' ' & dlls[di];
    end if;
    di += 1;
  end do;
  if copied <> '' then ?. 'runtime dlls:' & copied; end if;
end if;

var wi = 0;
while wi < warns.@count() do
  ?. 'warning: ' & warns[wi];
  wi += 1;
end do;
?. 'packed ' & zipN & ' files into ' & outFile &
   ' (' & z.length() & ' bytes payload)';
