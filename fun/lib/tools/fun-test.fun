// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-test: find and run a package's test files.
//
// Only the file name matters: every *_test.fun below the project root is a
// test, wherever it lives. Other .fun files are ordinary modules, so tests can
// share helpers. Each file runs in its own child interpreter; the runner
// writes a driver that imports the test library and the file, then calls
// runTests(). A project needs package.fun but not a bin entry.
use '../lib-host.fun';
use 'fun-tool-util.fun';
use 'fun-package-model.fun';

var _isWin = IsWindows();
var _nl = 10.toChar();
var _eol = _nl;
if _isWin then _eol = 13.toChar() & _nl; end if;
var _pid = UtilPid();
var _root = '';
var _tmp = '';
var _files = new [];
var _depDirs = new [];
var _report = new [];
var _maxLen = 0;
var _n = 0;
var _total = 0;
var _failed = 0;
var _fileFails = 0;
var _crashed = 0;
var _sumOk = false;
var _sumTotal = 0;
var _sumFailed = 0;

var _system = LibC().getapi('system', 's:i');
var _putenv;
var _setEnv;
var _exit;
var _exitProcess;
if _isWin then
  _setEnv = 'kernel32'.getapi('SetEnvironmentVariableA', 'ss:i');
  _exitProcess = 'kernel32'.getapi('ExitProcess', 'i:');
else
  _putenv = LibC().getapi('putenv', 's:i');
  _exit = LibC().getapi('exit', 'i:');
end if;

fun normPath(p)
  var t = p;
  if _isWin then t = t.replace(92.toChar(), '/'); end if;
  result = t;
end fun;

fun underDir(p, d)
  var a = normPath(p);
  var b = normPath(d);
  if _isWin then a = a.lower(); b = b.lower(); end if;
  if b = '' then result = false; return; end if;
  if a = b then result = true; return; end if;
  result = a.substr(0, b.length() + 1) = b & '/';
end fun;

// a name check only: tests are discovered by suffix, not by directory
fun isTestName(name)
  var n = name.lower();
  if n.length() < 9 then result = false; return; end if;
  result = n.substr(n.length() - 9) = '_test.fun';
end fun;

fun addDepDirs(root, m, names)
  var i = 0;
  while i < names.@count() do
    var d = nil;
    if m.dependencies <> nil then d = m.dependencies[names[i]]; end if;
    if d <> nil then
      var src = d.source or '';
      if src <> '' and not sourceIsGit(src) then
        _depDirs.@add(trimDir(HostFullPath(trimDir(root) & '/' & src)));
      end if;
    end if;
    i += 1;
  end do;
end fun;

// transitive names from the generated block; [] before the first tidy
fun resolvedNames(root)
  result = new [];
  var text = (trimDir(root) & '/package.fun').load();
  var ms = text.subpos('// >>> generated');
  if ms < 0 then return; end if;
  var me = text.substr(ms).subpos('// <<< generated');
  if me < 0 then return; end if;
  var block = text.substr(ms, me);
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

fun checkDepNames(names)
  var i = 0;
  while i < names.@count() do
    var n = names[i].lower();
    if n = 'test' or n = 'assert' then
      raise "test: dependency '" & names[i] & "' is reserved by the test library; rename it";
    end if;
    i += 1;
  end do;
end fun;

// alias of the use statement that starts at i, '' when it has none
fun useAlias(t, i)
  var j = i + 3;
  while j < t.length() do
    var c = t.substr(j, 1);
    if c = ';' or c = _nl then result = ''; return; end if;
    var re = -1;
    if c = '/' or c = '%' then re = skipRegex(t, j); end if;
    if re >= 0 then
      j = re;
    elsif c = '/' and t.substr(j + 1, 1) = '/' then
      j = skipLine(t, j);
    elsif c = '#' then
      j = skipComment(t, j);
    elsif c = "'" or c = '"' or c = '`' then
      j = skipString(t, j, c);
    elsif isAlpha(c) then
      var k = j;
      while k < t.length() and isIdent(t.substr(k, 1)) do k += 1; end do;
      if t.substr(j, k - j).lower() = 'as' then
        var a = k;
        while a < t.length() and isTrim(t.substr(a, 1)) do a += 1; end do;
        var b = a;
        while b < t.length() and isIdent(t.substr(b, 1)) do b += 1; end do;
        result = t.substr(a, b - a).lower();
        return;
      end if;
      j = k;
    else
      j += 1;
    end if;
  end do;
  result = '';
end fun;

// 'test' or 'assert' when a test file imports the library under a reserved name
fun reservedAlias(text)
  result = '';
  var i = 0;
  while i < text.length() do
    var c = text.substr(i, 1);
    var re = -1;
    if c = '/' or c = '%' then re = skipRegex(text, i); end if;
    if re >= 0 then
      i = re;
    elsif c = '/' and text.substr(i + 1, 1) = '/' then
      i = skipLine(text, i);
    elsif c = '#' then
      i = skipComment(text, i);
    elsif c = "'" or c = '"' or c = '`' then
      i = skipString(text, i, c);
    elsif isAlpha(c) then
      var j = i;
      while j < text.length() and isIdent(text.substr(j, 1)) do j += 1; end do;
      if text.substr(i, j - i).lower() = 'use' then
        var a = useAlias(text, i);
        if a = 'test' or a = 'assert' then result = a; return; end if;
      end if;
      i = j;
    else
      i += 1;
    end if;
  end do;
end fun;

fun checkTestFile(rel)
  var p = _root & '/' & rel;
  if p.subpos("'") >= 0 then
    raise "test: test file path cannot contain a quote: " & p;
  end if;
  var a = reservedAlias(p.load());
  if a <> '' then
    raise "test: " & rel & " imports with 'as " & a & "', a name reserved by the test library; use another alias";
  end if;
  var d = _root;
  var sl = rel.subpos('/');
  if sl >= 0 then d &= '/' & rel.substr(0, sl); end if;
  var shadow = d & '/test.fun';
  if UtilExists(shadow) then
    raise "test: " & shadow & " shadows the test library; rename it (module 'test.fun' is reserved)";
  end if;
end fun;

fun walkFiles(base, rel)
  var names = UtilListDir(base);
  var i = 0;
  while i < names.@count() do
    var nm = names[i];
    var p = base & '/' & nm;
    var skip = false;
    if UtilIsDir(p) then
      if nm.substr(0, 1) = '.' then skip = true; end if;
      if nm.lower() = 'dist' then skip = true; end if;
      var k = 0;
      while k < _depDirs.@count() do
        if underDir(p, _depDirs[k]) then skip = true; end if;
        k += 1;
      end do;
      if not skip then walkFiles(p, rel & nm & '/'); end if;
    else
      if not skip and isTestName(nm) then _files.@add(rel & nm); end if;
    end if;
    i += 1;
  end do;
end fun;

fun sortFiles()
  var i = 1;
  while i < _files.@count() do
    var v = _files[i];
    var j = i - 1;
    while j >= 0 and _files[j] > v do
      _files[j + 1] = _files[j];
      j -= 1;
    end do;
    _files[j + 1] = v;
    i += 1;
  end do;
end fun;

fun makeTempDir()
  var home = UtilFunHome() & 'tmp';
  UtilEnsureDir(home);
  var d = home & '/test-' & _pid;
  var n = 1;
  while UtilIsDir(d) do
    n += 1;
    d = home & '/test-' & _pid & '-' & n;
  end do;
  UtilEnsureDir(d);
  _tmp = d;
end fun;

fun findTestLib()
  var self = 1.arg();
  if self = '' then raise 'test: cannot locate the test library'; end if;
  var p = parentOf(parentOf(trimDir(HostFullPath(self)))) & '/test.fun';
  if p.subpos("'") >= 0 then
    raise "test: test library path cannot contain a quote: " & p;
  end if;
  if not UtilExists(p) then raise 'test: test library not found: ' & p; end if;
  result = p;
end fun;

fun writeShim()
  var lib = findTestLib();
  (_tmp & '/test.fun').save("use '" & lib & "';" & _nl);
end fun;

fun writeDriver(rel)
  var p = _root & '/' & rel;
  var body = "use 'test.fun';" & _nl &
             "use '" & p & "';" & _nl &
             'runTests();' & _nl;
  (_tmp & '/driver.fun').save(body);
end fun;

fun setEnv(name, val)
  if _isWin then
    _setEnv(name, val);
  else
    _putenv(name & '=' & val);
  end if;
end fun;

fun prepareEnv()
  setEnv('FUN_PACKAGE_READY', '');
  var fp = _tmp;
  var old = UtilEnv('FUN_PATH');
  if old <> '' then fp &= UtilPathSep() & old; end if;
  setEnv('FUN_PATH', fp);
end fun;

fun parseSummary(text)
  _sumOk = false;
  _sumTotal = 0;
  _sumFailed = 0;
  var pos = 0;
  while pos < text.length() do
    var e = text.substr(pos).subpos(_nl);
    var line = text.substr(pos);
    if e >= 0 then
      line = text.substr(pos, e);
      pos += e + 1;
    else
      pos = text.length();
    end if;
    if line.substr(0, 9) = '# tests: ' then
      var rest = line.substr(9);
      var p1 = rest.subpos(' passed: ');
      if p1 >= 0 then
        var r2 = rest.substr(p1 + 9);
        var p2 = r2.subpos(' failed: ');
        if p2 >= 0 then
          _sumTotal = rest.substr(0, p1).toNum();
          _sumFailed = r2.substr(p2 + 9).toNum();
          _sumOk = true;
        end if;
      end if;
    end if;
  end do;
end fun;

fun addFailureLines(text)
  var pos = 0;
  while pos < text.length() do
    var e = text.substr(pos).subpos(_nl);
    var line = text.substr(pos);
    if e >= 0 then
      line = text.substr(pos, e);
      pos += e + 1;
    else
      pos = text.length();
    end if;
    if line <> '' and line.substr(0, 3) <> 'ok ' and line.substr(0, 9) <> '# tests: ' then
      _report.@add(line);
    end if;
  end do;
end fun;

fun padTo(s, n)
  result = s;
  while result.length() < n do result &= ' '; end do;
end fun;

fun runTestFile(rel)
  _n += 1;
  writeDriver(rel);
  var log = _tmp & '/run-' & _n & '.log';
  var cmd = UtilQuote(0.arg()) & ' ' & UtilQuote(_tmp & '/driver.fun');
  var rc = UtilRunIn(_root, cmd, log);
  var text = '';
  if UtilExists(log) then text = log.load().replace(13.toChar(), ''); end if;
  parseSummary(text);
  if rc <> 0 or not _sumOk or _sumFailed > 0 then
    _fileFails += 1;
    if not _sumOk then _crashed += 1; end if;
    _report.@add(padTo(rel, _maxLen) & '   FAIL');
    if _sumOk then
      _total += _sumTotal;
      _failed += _sumFailed;
    end if;
    addFailureLines(text);
    if text = '' then
      _report.@add('no output from the test process (exit ' & rc & ')');
    end if;
  else
    _total += _sumTotal;
    _report.@add(padTo(rel, _maxLen) & '   PASS (' & _sumTotal & ')');
  end if;
end fun;

fun pluralWord(n, word)
  if n = 1 then result = '1 ' & word; else result = n & ' ' & word & 's'; end if;
end fun;

fun finishReport()
  var head = pluralWord(_files.@count(), 'file') & ', ' & pluralWord(_total, 'test');
  if _fileFails = 0 then
    _report.@add(head & ': all passed');
    return;
  end if;
  if _failed = 0 then
    var c = _crashed;
    if c = 0 then c = _fileFails; end if;
    _report.@add(head & ': ' & pluralWord(c, 'file') & ' failed to run');
    return;
  end if;
  var msg = head & ': ' & (_total - _failed) & ' passed, ' & _failed & ' failed';
  if _crashed > 0 then msg &= '; ' & pluralWord(_crashed, 'file') & ' failed to run'; end if;
  _report.@add(msg);
end fun;

fun reportText()
  result = '';
  var i = 0;
  while i < _report.@count() do
    if i > 0 then result &= _eol; end if;
    result &= _report[i];
    i += 1;
  end do;
end fun;

// The interpreter buffers stdout when it is redirected, so printing the report
// and then calling exit() would lose it. A child prints it and exits normally;
// only then does this process exit with the failure code.
fun printReport()
  var rp = _tmp & '/report.txt';
  var pp = _tmp & '/report.fun';
  rp.save(reportText());
  pp.save('?. 2.arg().load();' & _nl);
  setEnv('FUN_PACKAGE_READY', '1');
  var cmd = UtilQuote(0.arg()) & ' ' & UtilQuote(pp) & ' ' & UtilQuote(rp);
  if _isWin then cmd = '"' & cmd & '"'; end if;
  _system(cmd);
end fun;

fun cleanupTemp()
  if _tmp = '' then return; end if;
  try
    if UtilIsDir(_tmp) then UtilRemoveTree(_tmp); end if;
  except
  end try;
end fun;

fun runMain()
  var a = 2.arg();
  if a = '-h' or a = '--help' then
    ?. 'usage: fun test';
    result = false;
    return;
  end if;
  if a <> '' then raise "test: unknown argument '" & a & "'"; end if;

  if not UtilExists('package.fun') then
    raise 'test: package.fun not found in ' & _root;
  end if;

  var m = 'package.fun'.compile().package();
  var names = depNamesOf(_root);
  var rnames = resolvedNames(_root);
  addDepDirs(_root, m, names);

  walkFiles(_root, '');
  if _files.@count() = 0 then
    ?. 'no tests found';
    result = false;
    return;
  end if;
  sortFiles();

  checkDepNames(names);
  checkDepNames(rnames);
  var shadow = _root & '/test.fun';
  if UtilExists(shadow) then
    raise "test: " & shadow & " shadows the test library; rename it (module 'test.fun' is reserved)";
  end if;

  var i = 0;
  while i < _files.@count() do
    checkTestFile(_files[i]);
    if _files[i].length() > _maxLen then _maxLen = _files[i].length(); end if;
    i += 1;
  end do;

  makeTempDir();
  writeShim();
  prepareEnv();
  i = 0;
  while i < _files.@count() do
    runTestFile(_files[i]);
    i += 1;
  end do;
  finishReport();
  result = _fileFails > 0;
end fun;

var err = '';
var failed = false;
try
  _root = trimDir(HostCurrPath());
  failed = runMain();
except
  err = '' & @;
end try;
if err <> '' then
  cleanupTemp();
  raise err;
end if;
if failed then
  printReport();
  cleanupTemp();
  if _isWin then _exitProcess(1); else _exit(1); end if;
end if;
cleanupTemp();
var i = 0;
while i < _report.@count() do
  ?. _report[i];
  i += 1;
end do;
