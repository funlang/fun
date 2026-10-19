// End-to-end test for fun/lib/tools/fun-pack.fun: build a small project (entry,
// a local module, a repo-relative stdlib module and a resource file), pack it
// into one executable, run that executable and check what it wrote. Only
// booleans are printed, so the snapshot is the same on every host.
use 'fun/lib/lib-host.fun';
use 'fun/lib/lib-os.fun';

var sep = HostSep();
var nl  = 10.toChar();
var dq  = 34.toChar();

fun q(s)
  result = dq & s & dq;
end fun;

// project root = a fresh directory under the host temp dir; save() creates the
// missing parent directories on every host
var base = GetTempPath('fun-pack-test-' & GetPId() & sep);
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
(app & 'data.txt').save('EMB');   // embedded via use ':data.txt'
(app & 'stray.txt').save('keep-out');   // not declared with -a: must stay out

var out = base & 'packed';
if IsWindows() then out &= '.exe'; end if;
var resultFile = base & 'result.txt';

// 1. pack through the `fun pack` subcommand (its progress lines are hidden on
//    POSIX; the Windows launcher runs it in a hidden window)
var ps = 'pack ' & q(app & 'app.fun') & ' -a ' & q(app & 'res') & ' -o ' & q(out);
if not IsWindows() then ps &= ' >/dev/null 2>&1'; end if;
var rc = execWait(q(0.arg()), ps, HostCurrPath(), 0, false, 0, nil);
?. 'packed: ' & (rc = 0);
?. 'single file: ' & (out.size() > 0);

// 2. run the produced executable; 2.arg() of the script is the first real
//    argument, exactly as when the script is run by funcmd directly
var rc2 = execWait(q(out), q(resultFile), HostCurrPath(), 0, false, 0, nil);
?. 'ran: ' & (rc2 = 0);
?. 'output: ' & (resultFile.load() = '5|41|hello-resource|no|EMB');

// 3. the everyday flow: cd into the project and pack with a relative entry
//    while the interpreter lives elsewhere (absolute path)
fun absPath(p)
  result = p;
  if IsWindows() then
    if p.substr(1, 1) <> ':' then result = HostCurrPath() & sep & p; end if;
  else
    if p.substr(0, 1) <> '/' then result = HostCurrPath() & sep & p; end if;
  end if;
end fun;

var out2 = base & 'packed2';
if IsWindows() then out2 &= '.exe'; end if;
var ps2 = 'pack app.fun -a res -o ' & q(out2);
if not IsWindows() then ps2 &= ' >/dev/null 2>&1'; end if;
var rc3 = execWait(q(absPath(0.arg())), ps2, app, 0, false, 0, nil);
?. 'packed from project dir: ' & (rc3 = 0);
var resultFile2 = base & 'result2.txt';
var rc4 = execWait(q(out2), q(resultFile2), app, 0, false, 0, nil);
?. 'ran from project dir: ' & (rc4 = 0);
?. 'output 2: ' & (resultFile2.load() = '5|41|hello-resource|no|EMB');
