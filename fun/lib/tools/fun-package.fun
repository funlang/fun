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
use 'fun-tool-util.fun';
use 'fun-package-model.fun';

var _nl = 10.toChar();
var _facts = 'host'.arg().getJson(fd: true);
var _pid = UtilPid();

fun hasEntries(absDir)
  var names = UtilListDir(trimDir(absDir));
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

// --- manifest text editing ------------------------------------------------
// The manifest is user-edited Fun source, so add/remove touch only the
// dependencies set and leave every other byte alone; the scanner itself is
// shared with the run/pack tools (fun-package-model.fun).

fun linePad(t, pos)
  var i = pos;
  while i > 0 and t.substr(i - 1, 1) <> 10.toChar() do i -= 1; end do;
  var n = 0;
  while t.substr(i + n, 1) = ' ' do n += 1; end do;
  result = ' '.x(n);
end fun;

fun buildInner(entries, fieldIndent)
  if entries.@count() = 0 then result = ''; return; end if;
  var nl = 10.toChar();
  result = nl;
  var i = 0;
  while i < entries.@count() do
    if i > 0 then result &= ',' & nl; end if;
    var p = entries[i].subpos(31.toChar());
    result &= fieldIndent & '  ' & entries[i].substr(p + 1);
    i += 1;
  end do;
  result &= nl & fieldIndent;
end fun;

fun findEntry(entries, name)
  var i = 0;
  while i < entries.@count() do
    if entryName(entries[i]).lower() = name.lower() then result = i; return; end if;
    i += 1;
  end do;
  result = -1;
end fun;

// load the dependencies set once; add/remove mutate `entries` and save it
// back through saveDeps, which keeps the surrounding manifest bytes intact
fun loadDeps(tag)
  var d = new [];
  if not UtilExists('package.fun') then raise tag & ': package.fun not found'; end if;
  d.text = 'package.fun'.load();
  d.setAt = findDepOpen(d.text);
  if d.setAt < 0 then raise tag & ': dependencies field not found'; end if;
  d.setEnd = findBracketEnd(d.text, d.setAt);
  if d.setEnd < 0 then raise tag & ': dependencies set is not closed'; end if;
  d.indent = linePad(d.text, d.setAt);
  d.entries = parseEntries(d.text.substr(d.setAt + 1, d.setEnd - d.setAt - 2));
  result = d;
end fun;

fun saveDeps(d, entries)
  var backup = d.text;
  'package.fun'.save(replaceRange(d.text, d.setAt + 1, d.setEnd - 1, buildInner(entries, d.indent)));
  result = backup;
end fun;

fun replaceRange(t, startPos, endPos, s)
  result = t.substr(0, startPos) & s & t.substr(endPos);
end fun;

fun checkName(n)
  if not n.match(/^[a-z][a-z0-9_-]*$/) then
    raise "package: invalid name '" & n & "' (use [a-z][a-z0-9_-]*)";
  end if;
end fun;

fun checkValue(label, v)
  if v.subpos("'") >= 0 or v.subpos(10.toChar()) >= 0 or v.subpos(13.toChar()) >= 0 then
    raise 'package: ' & label & ' cannot contain quotes or newlines';
  end if;
end fun;

fun verifyAdd(name, src, ver)
  var m = 'package.fun'.compile().package();
  if m.dependencies = nil then result = false; return; end if;
  var d = m.dependencies[name];
  if d = nil then result = false; return; end if;
  result = (d.source or '') = src and (d.version or '') = ver;
end fun;

fun verifyRemove(name)
  var m = 'package.fun'.compile().package();
  if m.dependencies = nil then result = true; return; end if;
  result = m.dependencies[name] = nil;
end fun;

fun cmdAdd()
  var name = 3.arg();
  var src = 4.arg();
  if name = '' or src = '' then
    raise 'usage: fun package add <name> <source> [--version <v>]';
  end if;
  var ver = '';
  var ai = 5;
  while ai.arg() <> '' do
    if ai.arg() = '--version' then
      ver = (ai + 1).arg();
      if ver = '' then raise 'add: --version needs a value'; end if;
      ai += 2;
    else
      raise "add: unknown option '" & ai.arg() & "'";
    end if;
  end do;
  checkName(name);
  checkValue('source', src);
  checkValue('version', ver);
  var d = loadDeps('add');
  var entries = d.entries;
  var entry = "'" & name & "': [source: '" & src & "'";
  if ver <> '' then entry &= ", version: '" & ver & "'"; end if;
  entry &= ']';
  var idx = findEntry(entries, name);
  if idx >= 0 then
    entries[idx] = name & 31.toChar() & entry;
  else
    entries.@add(name & 31.toChar() & entry);
  end if;

  var backup = saveDeps(d, entries);
  var ok = false;
  try
    ok = verifyAdd(name, src, ver);
  except
    ok = false;
  end try;
  if not ok then
    'package.fun'.save(backup);
    raise 'add: could not update package.fun safely; the file was restored';
  end if;
  ?. "added '" & name & "'; run 'fun package tidy' to install";
end fun;

fun cmdRemove()
  var name = 3.arg();
  if name = '' then raise 'usage: fun package remove <name>'; end if;
  if 4.arg() <> '' then raise "remove: unexpected argument '" & 4.arg() & "'"; end if;
  checkName(name);
  var d = loadDeps('remove');
  var entries = d.entries;
  var idx = findEntry(entries, name);
  if idx < 0 then raise "remove: dependency '" & name & "' not found"; end if;

  var kept = new [];
  var i = 0;
  while i < entries.@count() do
    if i <> idx then kept.@add(entries[i]); end if;
    i += 1;
  end do;

  var backup = saveDeps(d, kept);
  var ok = false;
  try
    ok = verifyRemove(name);
  except
    ok = false;
  end try;
  if not ok then
    'package.fun'.save(backup);
    raise 'remove: could not update package.fun safely; the file was restored';
  end if;
  ?. "removed '" & name & "'; run 'fun package tidy' to clean up";
end fun;

// --- dependency resolution / cache ---------------------------------------
// Global arrays (rather than records) keep every helper's result explicit:
// name, echoed source, declared version, commit, hash, commit date, dir, lib.

var _rsNames = new [];
var _rsSrc = new [];
var _rsVer = new [];
var _rsCommit = new [];
var _rsHash = new [];
var _rsAt = new [];
var _rsDir = new [];
var _rsLib = new [];
var _rsSeen = new [];
var _rsOld = nil;
var _rsLog = '';

fun rsFind(name)
  var v = _rsSeen[name];
  if v = nil then result = -1; else result = v - 1; end if;
end fun;

fun rsAdd(name, src, ver, commit, hash, at, dir, lib)
  checkValue('source', src);
  if commit <> '' then checkValue('commit', commit); end if;
  if hash <> '' then checkValue('hash', hash); end if;
  var idx = _rsNames.@count();
  _rsNames.@add(name);
  _rsSrc.@add(src);
  _rsVer.@add(ver);
  _rsCommit.@add(commit);
  _rsHash.@add(hash);
  _rsAt.@add(at);
  _rsDir.@add(dir);
  _rsLib.@add(lib);
  _rsSeen[name] = idx + 1;
  result = idx;
end fun;

fun logTail(p)
  result = '';
  if UtilExists(p) then
    var s = p.load().replace(13.toChar(), '').replace(10.toChar(), ' | ');
    if s.length() > 240 then s = s.substr(0, 240); end if;
    result = s;
  end if;
end fun;

fun gitOut(dir, cmd, logFile)
  var rc = UtilRunIn(dir, 'git ' & cmd, logFile);
  if rc <> 0 then raise 'package: git ' & cmd & ' failed: ' & logTail(logFile); end if;
  result = trimText(logFile.load().replace(13.toChar(), '').replace(10.toChar(), ''));
end fun;

// No '%' on purpose: commands run through a batch file on Windows, where a
// percent sign is expanded by cmd before git ever sees it.
fun hashOfTree(dir, logFile)
  var rc = UtilRunIn(dir, 'git cat-file -p HEAD', logFile);
  if rc <> 0 then raise 'package: git cat-file -p HEAD failed: ' & logTail(logFile); end if;
  var text = logFile.load();
  var nl = text.subpos(10.toChar());
  if nl < 0 then nl = text.length(); end if;
  var line = text.substr(0, nl);
  if line.substr(0, 5) <> 'tree ' then raise 'package: cannot read the tree hash: ' & line; end if;
  result = trimText(line.substr(5));
end fun;

fun commitDate(dir, logFile)
  var rc = UtilRunIn(dir, 'git show -s --date=short HEAD', logFile);
  if rc <> 0 then
    raise 'package: git show -s --date=short HEAD failed: ' & logTail(logFile);
  end if;
  var text = logFile.load();
  var at = text.subpos('Date:');
  if at < 0 then raise 'package: cannot read the commit date'; end if;
  var rest = text.substr(at + 5);
  var nl = rest.subpos(10.toChar());
  if nl >= 0 then rest = rest.substr(0, nl); end if;
  result = trimText(rest);
end fun;

// a cached tag or commit is reusable without network; branches are not
// (their head may have moved, and only a clone can tell)
fun findCached(src, ver)
  result = '';
  if ver = '' then return; end if;
  var key = sourceKey(src);
  var repo = baseName(key);
  var base = UtilFunHome() & 'packages';
  var par = parentOf(key);
  if par <> '' then base &= '/' & par; end if;
  if not UtilIsDir(base) then return; end if;
  var names = UtilListDir(base);
  var i = 0;
  while i < names.@count() do
    var nm = names[i];
    if nm.substr(0, repo.length() + 1) = repo & '@' then
      var commit = nm.substr(repo.length() + 1);
      var match = false;
      if commit = ver then
        match = true;
      elsif ver.match(/^[0-9a-fA-F]+$/) and ver.length() >= 7 and commit.substr(0, ver.length()) = ver then
        match = true;
      else
        var rc = UtilRunIn(base & '/' & nm, 'git rev-parse --verify ' & UtilQuote('refs/tags/' & ver), _rsLog);
        if rc = 0 then
          var got = trimText(_rsLog.load().replace(13.toChar(), '').replace(10.toChar(), ''));
          if got = commit then match = true; end if;
        end if;
      end if;
      if match then
        result = base & '/' & nm;
        return;
      end if;
    end if;
    i += 1;
  end do;
end fun;

// Git is only needed when a git dependency is resolved; path-only manifests
// keep working on machines without git. Run/pack never reach this (they read
// the cache), so the check lives in tidy's fetch path.
var _gitReady = false;
fun requireGit(name)
  if _gitReady then return; end if;
  var tmpDir = UtilFunHome() & 'tmp';
  UtilEnsureDir(tmpDir);
  var log = tmpDir & '/git-' & _pid & '.log';
  var rc = UtilRunIn(tmpDir, 'git --version', log);
  if rc <> 0 then
    if UtilExists(log) then log.move(); end if;
    if UtilExists(log & '.bat') then (log & '.bat').move(); end if;
    raise "package: git not found in PATH; install git or add it to PATH and try again (needed for dependency '" & name & "')";
  end if;
  _gitReady = true;
  if UtilExists(log) then log.move(); end if;
  if UtilExists(log & '.bat') then (log & '.bat').move(); end if;
end fun;

fun fetchGit(name, src, ver)
  requireGit(name);
  var pin = nil;
  if _rsOld <> nil then pin = _rsOld[name]; end if;
  var pinned = '';
  if pin <> nil and (pin.source or '') = src and (pin.version or '') = ver then
    pinned = pin.commit or '';
  end if;
  var dir = '';
  if pinned <> '' then dir = cacheDirFor(src, pinned); end if;
  if pinned <> '' and UtilIsDir(dir) then
    var tree = hashOfTree(dir, _rsLog);
    var at = commitDate(dir, _rsLog);
    var hash = 'git-tree:' & tree;
    if pin.hash <> nil and (pin.hash or '') <> '' and (pin.hash or '') <> hash then
      raise "package: cache for '" & name & "' is corrupted; remove " & dir & ' and run tidy again';
    end if;
    result = rsAdd(name, src, ver, pinned, hash, at, dir, readLib(dir, name));
    return;
  end if;

  if pinned = '' then
    var cached = findCached(src, ver);
    if cached <> '' then
      var ccommit = gitOut(cached, 'rev-parse HEAD', _rsLog);
      var ctree = hashOfTree(cached, _rsLog);
      var cat = commitDate(cached, _rsLog);
      result = rsAdd(name, src, ver, ccommit, 'git-tree:' & ctree, cat, cached, readLib(cached, name));
      return;
    end if;
  end if;

  var dl = UtilFunHome() & 'cache/download';
  UtilEnsureDir(dl);
  var tmp = dl & 'clone-' & _pid;
  if UtilIsDir(tmp) then UtilRemoveTree(tmp); end if;
  var rc = UtilRunIn(dl, 'git clone ' & UtilQuote(src) & ' ' & UtilQuote(tmp), _rsLog);
  if rc <> 0 then
    if UtilIsDir(tmp) then UtilRemoveTree(tmp); end if;
    raise "package: git clone failed for '" & name & "': " & logTail(_rsLog);
  end if;
  var ref = pinned;
  if ref = '' then ref = ver; end if;
  if ref <> '' then
    rc = UtilRunIn(tmp, 'git checkout ' & UtilQuote(ref), _rsLog);
    if rc <> 0 then
      UtilRemoveTree(tmp);
      raise "package: version '" & ref & "' not found for '" & name & "': " & logTail(_rsLog);
    end if;
  end if;
  var commit = gitOut(tmp, 'rev-parse HEAD', _rsLog);
  if pinned <> '' and commit <> pinned then
    UtilRemoveTree(tmp);
    raise "package: '" & name & "' did not resolve to the pinned commit " & pinned;
  end if;
  var tree = hashOfTree(tmp, _rsLog);
  var at = commitDate(tmp, _rsLog);
  var dest = cacheDirFor(src, commit);
  var lib = readLib(tmp, name);
  if UtilIsDir(dest) then
    UtilRemoveTree(tmp);
  else
    UtilEnsureDir(parentOf(dest));
    tmp.move(dest);
  end if;
  result = rsAdd(name, src, ver, commit, 'git-tree:' & tree, at, dest, lib);
end fun;

fun resolveDep(parentDir, m, name)
  var decl = pkgDecl(parentDir, m, name, 'package');
  var src = decl.src;
  var ver = decl.ver;
  var git = decl.git;
  var eff = decl.eff;

  var idx = rsFind(name);
  if idx >= 0 then
    if _rsSrc[idx] <> eff or _rsVer[idx] <> ver then
      raise "package: version conflict for '" & name & "' (" & _rsSrc[idx] & '@' & _rsVer[idx] &
            ' vs ' & eff & '@' & ver & ')';
    end if;
    return;
  end if;

  if git then
    fetchGit(name, src, ver);
  else
    if not UtilIsDir(eff) then raise "package: path dependency '" & name & "' not found: " & eff; end if;
    rsAdd(name, eff, '', '', '', '', eff, readLib(eff, name));
  end if;

  var idx2 = rsFind(name);
  var dir = _rsDir[idx2];
  var dm = readPkg(dir);
  var names = depNamesOf(dir);
  var i = 0;
  while i < names.@count() do
    resolveDep(dir, dm, names[i]);
    i += 1;
  end do;
end fun;

fun oldResolvedNames(text)
  result = new [];
  var ms = text.subpos('// >>> generated');
  if ms < 0 then return; end if;
  var np = text.substr(ms).subpos(10.toChar());
  if np < 0 then return; end if;
  var start = ms + np + 1;
  var me = text.substr(start).subpos('// <<< generated');
  if me < 0 then return; end if;
  var block = text.substr(start, me);
  var at = block.subpos('resolved:');
  if at < 0 then return; end if;
  var op = block.substr(at).subpos('[');
  if op < 0 then return; end if;
  op += at;
  var en = findBracketEnd(block, op);
  if en < 0 then return; end if;
  var entries = parseEntries(block.substr(op + 1, en - op - 2));
  var i = 0;
  while i < entries.@count() do
    result.@add(entryName(entries[i]));
    i += 1;
  end do;
end fun;

fun rsLine(i)
  var s = "'" & _rsNames[i] & "': [source: '" & _rsSrc[i] & "'";
  if _rsVer[i] <> '' then s &= ", version: '" & _rsVer[i] & "'"; end if;
  if _rsCommit[i] <> '' then s &= ", commit: '" & _rsCommit[i] & "'"; end if;
  if _rsHash[i] <> '' then s &= ", hash: '" & _rsHash[i] & "'"; end if;
  if _rsAt[i] <> '' then s &= ", at: '" & _rsAt[i] & "'"; end if;
  s &= ']';
  result = s;
end fun;

fun resolvedBlock(text)
  var nl = 10.toChar();
  var ms = text.subpos('// >>> generated');
  if ms < 0 then raise 'tidy: generated start marker not found'; end if;
  var indent = linePad(text, ms);
  if _rsNames.@count() = 0 then
    result = indent & 'resolved: []' & nl;
    return;
  end if;
  result = indent & 'resolved: [' & nl;
  var i = 0;
  while i < _rsNames.@count() do
    result &= indent & '  ' & rsLine(i) & ',' & nl;
    i += 1;
  end do;
  result &= indent & ']' & nl;
end fun;

fun replaceResolved(text, block)
  var ms = text.subpos('// >>> generated');
  if ms < 0 then raise 'tidy: generated start marker not found'; end if;
  var np = text.substr(ms).subpos(10.toChar());
  if np < 0 then raise 'tidy: generated start marker has no newline'; end if;
  var start = ms + np + 1;
  var me = text.substr(start).subpos('// <<< generated');
  if me < 0 then raise 'tidy: generated end marker not found'; end if;
  var endPos = start + me;
  var k = endPos;
  while k > start and text.substr(k - 1, 1) <> 10.toChar() do k -= 1; end do;
  result = text.substr(0, start) & block & text.substr(k);
end fun;

fun cmdTidy()
  if not UtilExists('package.fun') then raise 'tidy: package.fun not found in ' & HostCurrPath(); end if;
  var text = 'package.fun'.load();
  var m = 'package.fun'.compile().package();
  _rsOld = m.resolved;
  var tmpDir = UtilFunHome() & 'tmp';
  UtilEnsureDir(tmpDir);
  _rsLog = tmpDir & '/tidy-' & _pid & '.log';

  var root = HostCurrPath();
  var names = depNamesOf(root);
  var i = 0;
  while i < names.@count() do
    resolveDep(root, m, names[i]);
    i += 1;
  end do;

  var oldNames = oldResolvedNames(text);
  var changed = false;
  var report = '';
  i = 0;
  while i < _rsNames.@count() do
    var old = nil;
    if _rsOld <> nil then old = _rsOld[_rsNames[i]]; end if;
    var same = false;
    if old <> nil then
      same = (old.source or '') = _rsSrc[i] and (old.version or '') = _rsVer[i] and
             (old.commit or '') = _rsCommit[i] and (old.hash or '') = _rsHash[i];
    end if;
    if same then
      if (old.at or '') <> '' then _rsAt[i] = old.at; end if;
    else
      changed = true;
      if old = nil then report &= ' installed ' & _rsNames[i]; else report &= ' updated ' & _rsNames[i]; end if;
    end if;
    i += 1;
  end do;
  i = 0;
  while i < oldNames.@count() do
    if rsFind(oldNames[i]) < 0 then changed = true; report &= ' removed ' & oldNames[i]; end if;
    i += 1;
  end do;

  if not changed then
    ?. 'up to date';
  else
    var block = resolvedBlock(text);
    var backup = text;
    'package.fun'.save(replaceResolved(text, block));
    var ok = false;
    try
      var m2 = 'package.fun'.compile().package();
      ok = true;
      var j = 0;
      while j < _rsNames.@count() do
        var r = nil;
        if m2.resolved <> nil then r = m2.resolved[_rsNames[j]]; end if;
        if r = nil or (r.commit or '') <> _rsCommit[j] then ok = false; end if;
        j += 1;
      end do;
    except
      ok = false;
    end try;
    if not ok then
      'package.fun'.save(backup);
      raise 'tidy: could not write resolved safely; the file was restored';
    end if;
    ?. 'tidy:' & report;
  end if;
  if UtilExists(_rsLog) then _rsLog.move(); end if;
end fun;

fun usage()
  ?. 'usage: fun package <command>';
  ?. '';
  ?. '  init [dir] [--bin|--lib]  create package.fun (default: .)';
  ?. '  add <name> <source> [--version <v>]';
  ?. '  remove <name>';
  ?. '  tidy';
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
  var existing = UtilIsDir(target);
  if not existing and UtilExists(target) then
    raise 'init: not a directory: ' & target;
  end if;
  var manifest = target & '/package.fun';
  if UtilExists(manifest) then
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
elsif cmd = 'add' then
  cmdAdd();
elsif cmd = 'remove' then
  cmdRemove();
elsif cmd = 'tidy' then
  cmdTidy();
elsif cmd = '' or cmd = '-h' or cmd = '--help' then
  usage();
else
  raise "package: unknown command '" & cmd & "'";
end if;
