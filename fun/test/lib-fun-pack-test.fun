// End-to-end test for fun/lib/tools/fun-pack.fun: build a small project (entry,
// a local module, a repo-relative stdlib module, an embedded data file, a
// declared resource and an undeclared stray file), pack it through `fun pack`,
// run the produced executable and check what it wrote. Only booleans are
// printed on success, so the snapshot is the same on every host; a failing run
// adds an rc/err line (and never crashes on the missing output file).
//
// lib-os is deliberately avoided: its Windows backend creates WScript.Shell at
// load time (COM newobj), which the FPC Windows build does not provide. Process
// spawning goes through the C runtime's system() instead, and the temp dir
// comes from lib-host.
use 'fun/lib/lib-host.fun';

var _isWin = IsWindows();
var sep    = HostSep();
var nl     = 10.toChar();
var dq     = 34.toChar();

fun q(s)
  result = dq & s & dq;
end fun;

var _getpid;
var _system;
if _isWin then
  _getpid = 'kernel32'.getapi('GetCurrentProcessId', ':i');
  _system = LibC().getapi('system', 'a:i');   // ANSI command line on Windows
else
  _getpid = LibC().getapi('getpid', ':i');
  _system = LibC().getapi('system', 's:i');
end if;
var _pid = _getpid();

// run cmd in dir and return its exit code; all output goes to logFile so the
// snapshot stays free of temp paths (system() returns the raw wait status on
// POSIX and the command exit code on Windows).
//
// Windows runs the command through a generated .bat: cmd /c rewrites commands
// that start with a quote (it strips the first and last quote), which broke the
// redirection and the arguments.
fun runIn(dir, cmd, logFile)
  if _isWin then
    var crlf = 13.toChar() & 10.toChar();
    var bat  = logFile & '.bat';
    var body = '@echo off' & crlf;
    if dir <> '' then body &= 'cd /d ' & q(dir) & crlf; end if;
    body &= cmd & ' >' & q(logFile) & ' 2>&1' & crlf;
    bat.save(body);
    result = _system(q(q(bat)));   // ""...bat"" survives cmd's quote rules
  else
    var c = cmd;
    if dir <> '' then c = 'cd ' & q(dir) & ' && ' & c; end if;
    c &= ' >' & q(logFile) & ' 2>&1';
    result = _system(c) div 256;
  end if;
end fun;

// diagnostics for a failed step. Lines carry "failed" because the Windows CI
// runner only forwards log lines matching FAIL/failed/mismatch to the check-run
// annotation, which is the only readable view of that job.
fun yn(p)
  result = false;
  try
    var probe = p.load(cp: 0xffff);   // load-based: find() is unreliable on Windows
    result = true;
  except
  end try;
end fun;

fun dirOf(p)
  var i = p.length() - 1;
  while i >= 0 do
    var ch = p.substr(i, 1);
    if ch = '/' or ch = 92.toChar() then
      result = p.substr(0, i + 1);
      exit;
    end if;
    i -= 1;
  end do;
end fun;

fun logTail(p)
  result = '';
  if yn(p) then
    var s = p.load().replace(nl, ' | ');
    if s.length() > 300 then s = s.substr(0, 300); end if;
    result = s;
  end if;
end fun;

fun fail(tag, rc, logFile, base)
  if rc <> 0 then
    ?. 'failed ' & tag & ': rc=' & rc;
    ?. 'failed ' & tag & ' log: ' & logTail(logFile);
    ?. 'failed ' & tag & ' dlls: pcre3=' & yn(base & 'pcre3.dll') &
       ' ffi=' & yn(base & 'ffi.dll');
  end if;
end fun;

fun loadIf(p)
  result = '';
  if yn(p) then result = p.load(); end if;
end fun;

fun absPath(p)
  result = p;
  if _isWin then
    if p.substr(1, 1) <> ':' then result = HostCurrPath() & sep & p; end if;
  else
    if p.substr(0, 1) <> '/' then result = HostCurrPath() & sep & p; end if;
  end if;
end fun;

// project root = a fresh directory under the host temp dir; save() creates the
// missing parent directories on every host
var base = HostTempPath('fun-pack-test-' & _pid & sep);
var app  = base & 'app' & sep;
var res  = app & 'res' & sep;

(app & 'app.fun').save("use 'util.fun';" & nl &
  "use ':data.txt' as d;" & nl &
  "use 'fun/lib/lib-utils.fun';" & nl &
  "var r = 'res/hello.txt'.load();" & nl &
  "var extra = 'no';" & nl &
  "if 'stray.txt'.find() then extra = 'yes'; end if;" & nl &
  "var outArg = 2.arg();" & nl &
  "if outArg = '' then" & nl &
  "  (0.arg() & '.diag').save('no-arg|entry=' & 1.arg() & '|next=' & 3.arg());" & nl &
  "else" & nl &
  "  outArg.save(Add(2, 3) & '|' & str2hex('A') & '|' & r & '|' & extra & '|' & d);" & nl &
  "end if;" & nl);
(app & 'util.fun').save("fun Add(a, b)" & nl &
  "  result = a + b;" & nl &
  "end fun;" & nl);
(res & 'hello.txt').save('hello-resource');
(app & 'data.txt').save('EMB');         // embedded via use ':data.txt'
(app & 'stray.txt').save('keep-out');   // not declared with -a: must stay out

var funcmdAbs = absPath(0.arg());
var funcmd    = q(funcmdAbs);
var expect    = '5|41|hello-resource|no|EMB';

// 1. pack through the `fun pack` subcommand (absolute entry)
var out = base & 'packed';
if _isWin then out &= '.exe'; end if;
var resultFile = base & 'result.txt';
var rc = runIn(HostCurrPath(), funcmd & ' pack ' & q(app & 'app.fun') &
               ' -a ' & q(app & 'res') & ' -o ' & q(out), base & 'pack1.log');
?. 'packed: ' & (rc = 0);
?. 'single file: ' & (out.size() > 0);
fail('pack', rc, base & 'pack1.log', base);
if rc = 0 and not (out.size() > 0) then ?. 'failed pack: no output file'; end if;

// 2. run the produced executable; 2.arg() of the script is the first real
//    argument, exactly as when the script is run by funcmd directly
var rc2 = runIn('', q(out) & ' ' & q(resultFile), base & 'run1.log');
?. 'ran: ' & (rc2 = 0);
var got = loadIf(resultFile);
?. 'output: ' & (got = expect);
fail('run', rc2, base & 'run1.log', base);
if got <> expect then
  ?. 'failed output: [' & got & ']';
  ?. 'failed diag: ' & logTail(out & '.diag');
  ?. 'failed pack log: ' & logTail(base & 'pack1.log');
  ?. 'failed selfcheck: ' & yn(funcmdAbs);
  ?. 'failed runtime pcre3: ' & yn(dirOf(funcmdAbs) & 'pcre3.dll');
end if;

// 3. the everyday flow: cd into the project and pack with a relative entry
//    while the interpreter lives elsewhere (absolute path)
var out2 = base & 'packed2';
if _isWin then out2 &= '.exe'; end if;
var rc3 = runIn(app, funcmd & ' pack app.fun -a res -o ' & q(out2), base & 'pack2.log');
?. 'packed from project dir: ' & (rc3 = 0);
fail('pack2', rc3, base & 'pack2.log', base);
var resultFile2 = base & 'result2.txt';
var rc4 = runIn('', q(out2) & ' ' & q(resultFile2), base & 'run2.log');
?. 'ran from project dir: ' & (rc4 = 0);
var got2 = loadIf(resultFile2);
?. 'output 2: ' & (got2 = expect);
fail('run2', rc4, base & 'run2.log', base);
if got2 <> expect then
  ?. 'failed output 2: [' & got2 & ']';
  ?. 'failed diag 2: ' & logTail(out2 & '.diag');
  ?. 'failed pack2 log: ' & logTail(base & 'pack2.log');
  ?. 'failed runtime pcre3 2: ' & yn(dirOf(funcmdAbs) & 'pcre3.dll');
end if;
