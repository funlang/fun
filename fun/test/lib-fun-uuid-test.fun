// End-to-end test for fun/lib/uuid.fun. The UUID checks themselves live in
// fun/test/fun-uuid/ and run through `fun test`; this wrapper only proves the
// project run succeeds on every host (including the Windows RNG path).
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
  _system = LibC().getapi('system', 'a:i');
else
  _getpid = LibC().getapi('getpid', ':i');
  _system = LibC().getapi('system', 's:i');
end if;
var _pid = _getpid();
var _funHome = '';

fun runIn(dir, cmd, logFile)
  if _isWin then
    var crlf = 13.toChar() & nl;
    var bat  = logFile & '.bat';
    var body = '@echo off' & crlf;
    if dir <> '' then body &= 'cd /d ' & q(dir) & crlf; end if;
    if _funHome <> '' then body &= 'set "FUN_HOME=' & _funHome & '"' & crlf; end if;
    body &= cmd & ' >' & q(logFile) & ' 2>&1' & crlf;
    bat.save(body);
    result = _system(q(q(bat)));
  else
    var c = cmd;
    if _funHome <> '' then c = 'FUN_HOME=' & q(_funHome) & ' ' & c; end if;
    if dir <> '' then c = 'cd ' & q(dir) & ' && ' & c; end if;
    c &= ' >' & q(logFile) & ' 2>&1';
    result = _system(c) div 256;
  end if;
end fun;

fun loadIf(p)
  result = '';
  try
    result = p.load();
  except
  end try;
end fun;

fun line(s)
  result = s.replace(13.toChar(), '').replace(nl, ' ');
end fun;

fun has(s, part)
  result = s.subpos(part) >= 0;
end fun;

fun absPath(p)
  result = p;
  if _isWin then
    if p.substr(1, 1) <> ':' then result = HostCurrPath() & sep & p; end if;
  else
    if p.substr(0, 1) <> '/' then result = HostCurrPath() & sep & p; end if;
  end if;
end fun;

var base = HostTempPath('fun-uuid-test-' & _pid & sep);
(base & '.seed').save('x');
_funHome = base & 'funhome';
var funcmd = q(absPath(0.arg()));
var proj = HostCurrPath() & sep & 'fun' & sep & 'test' & sep & 'fun-uuid';
var log = base & 'run.log';

var rc = runIn(proj, funcmd & ' test', log);
var out = loadIf(log);
var okRun = rc = 0;
var okPass = has(out, 'PASS (3)');
var okSum = has(out, '1 file, 3 tests: all passed');

?. 'uuid project runs: ' & okRun;
?. 'uuid tests pass: ' & okPass;
?. 'uuid summary: ' & okSum;
if not okRun or not okPass or not okSum then
  ?. 'failed uuid detail: rc=' & rc & ' out=[' & line(out) & ']';
end if;
