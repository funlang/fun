// End-to-end test for fun/lib/tools/fun-pack.fun: build a small project (entry,
// a local module, a repo-relative stdlib module, an embedded data file, a
// declared resource and an undeclared stray file), pack it through `fun pack`,
// run the produced executable and check what it wrote. Only booleans are
// printed, so the snapshot is the same on every host.
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

var _pid;
var _system;
if _isWin then
  _pid    = 'kernel32'.getapi('GetCurrentProcessId', ':i');
  _system = LibC().getapi('system', 'a:i');   // ANSI command line on Windows
else
  _pid    = LibC().getapi('getpid', ':i');
  _system = LibC().getapi('system', 's:i');
end if;

// run cmd in dir and return its exit code; the output is discarded so the
// snapshot never carries temp paths (system() returns the raw wait status on
// POSIX, the command exit code on Windows)
fun runIn(dir, cmd)
  var c = cmd;
  if dir <> '' then
    if _isWin then
      c = 'cd /d ' & q(dir) & ' && ' & c;
    else
      c = 'cd ' & q(dir) & ' && ' & c;
    end if;
  end if;
  if _isWin then c &= ' >NUL 2>&1'; else c &= ' >/dev/null 2>&1'; end if;
  var rc = _system(c);
  if _isWin then result = rc; else result = rc div 256; end if;
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
  "2.arg().save(Add(2, 3) & '|' & str2hex('A') & '|' & r & '|' & extra & '|' & d);" & nl);
(app & 'util.fun').save("fun Add(a, b)" & nl &
  "  result = a + b;" & nl &
  "end fun;" & nl);
(res & 'hello.txt').save('hello-resource');
(app & 'data.txt').save('EMB');         // embedded via use ':data.txt'
(app & 'stray.txt').save('keep-out');   // not declared with -a: must stay out

var funcmd = q(absPath(0.arg()));

// 1. pack through the `fun pack` subcommand (absolute entry)
var out = base & 'packed';
if _isWin then out &= '.exe'; end if;
var resultFile = base & 'result.txt';
var rc = runIn(HostCurrPath(), funcmd & ' pack ' & q(app & 'app.fun') &
               ' -a ' & q(app & 'res') & ' -o ' & q(out));
?. 'packed: ' & (rc = 0);
?. 'single file: ' & (out.size() > 0);

// 2. run the produced executable; 2.arg() of the script is the first real
//    argument, exactly as when the script is run by funcmd directly
var rc2 = runIn('', q(out) & ' ' & q(resultFile));
?. 'ran: ' & (rc2 = 0);
?. 'output: ' & (resultFile.load() = '5|41|hello-resource|no|EMB');

// 3. the everyday flow: cd into the project and pack with a relative entry
//    while the interpreter lives elsewhere (absolute path)
var out2 = base & 'packed2';
if _isWin then out2 &= '.exe'; end if;
var rc3 = runIn(app, funcmd & ' pack app.fun -a res -o ' & q(out2));
?. 'packed from project dir: ' & (rc3 = 0);
var resultFile2 = base & 'result2.txt';
var rc4 = runIn('', q(out2) & ' ' & q(resultFile2));
?. 'ran from project dir: ' & (rc4 = 0);
?. 'output 2: ' & (resultFile2.load() = '5|41|hello-resource|no|EMB');
