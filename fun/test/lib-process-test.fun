// process: child execution, stdio capture, exit status and timeout.
use 'fun/lib/process.fun';

var host = 'host'.arg().getJson(fd: true);
var win = host.os = 'windows';

fun check(r)
  result = r.ok = true and r.exitCode = 0 and r.signal = nil and r.timedOut = false;
end fun;

// basic stdout
var r;
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'echo hello']);
else
  r = process.run('/bin/sh', ['-c', 'echo hello']);
end if;
?. check(r);
?. r.stdout.subpos('hello') >= 0;
?. r.stderr = '';

// arguments containing spaces
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'echo a b']);
else
  r = process.run('/bin/sh', ['-c', 'printf "%s" "a b"']);
end if;
?. r.ok;
?. r.stdout.subpos('a b') >= 0;

// cwd
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'cd'], [cwd: 'C:\']);
  ?. r.ok;
  ?. r.stdout.subpos('C:') >= 0;
else
  r = process.run('/bin/pwd', [], [cwd: '/tmp']);
  ?. r.ok;
  ?. r.stdout.subpos('/tmp') >= 0;
end if;

// non-zero exit
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'exit 7']);
else
  r = process.run('/bin/sh', ['-c', 'exit 7']);
end if;
?. r.ok = false;
?. r.exitCode = 7;
?. r.timedOut = false;

// stderr
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'echo out & echo err 1>&2']);
else
  r = process.run('/bin/sh', ['-c', 'echo out; echo err >&2']);
end if;
?. r.ok = true;
?. r.stdout.subpos('out') >= 0;
?. r.stderr.subpos('err') >= 0;
?. r.stdout.subpos('err') < 0;

// stdin
if win then
  r = process.run('findstr.exe', ['.'], [stdin: 'abc' + 13.toChar() + 10.toChar()]);
else
  r = process.run('/bin/sh', ['-c', 'cat'], [stdin: 'abc']);
end if;
?. r.ok = true;
?. r.stdout.subpos('abc') >= 0;

// large stdin
if win then
  var line = 'x'.x(50) & 13.toChar() & 10.toChar();
  var big = line.x(2000);
  r = process.run('findstr.exe', ['.'], [stdin: big, timeout: 5000]);
  ?. r.ok;
  ?. r.stdout.length() > 90000;
else
  var big = 'x'.x(200000);
  r = process.run('/bin/cat', [], [stdin: big, timeout: 5000]);
  ?. r.ok;
  ?. r.stdout.length() = 200000;
end if;

// empty stdin
if not win then
  r = process.run('/bin/sh', ['-c', 'cat'], [stdin: '']);
  ?. r.ok;
  ?. r.stdout = '';
else
  ?. true;
  ?. true;
end if;

// binary bytes
if not win then
  r = process.run('/bin/sh', ['-c', 'printf "A\\001B"']);
  ?. r.ok;
  ?. r.stdout.length() = 3;
  ?. r.stdout.toByte(1) = 1;
else
  ?. true;
  ?. true;
  ?. true;
end if;

// missing command raises a start error
var bad = false;
try
  process.run('__fun_no_such_command__', []);
except
  bad = ('' & @).subpos('process: start failed') >= 0;
end try;
?. bad;

// a failed start does not break the next run
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'echo ok']);
else
  r = process.run('/bin/echo', ['ok']);
end if;
?. r.ok;

// timeout
if win then
  r = process.run('ping.exe', ['-n', '6', '127.0.0.1'], [timeout: 300]);
else
  r = process.run('/bin/sh', ['-c', 'sleep 5'], [timeout: 300]);
end if;
?. r.ok = false;
?. r.timedOut = true;

// partial output survives a timeout
if win then
  ?. true;
  ?. true;
else
  r = process.run('/bin/sh', ['-c', 'printf before; sleep 5'], [timeout: 300]);
  ?. r.timedOut;
  ?. r.stdout = 'before';
end if;

// large output crosses the pipe buffer
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'for /L %i in (1,1,20000) do @echo x']);
  ?. r.ok;
  ?. r.stdout.length() > 10000;
else
  r = process.run('/bin/dd', ['if=/dev/zero', 'bs=1024', 'count=200']);
  ?. r.ok;
  ?. r.stdout.length() = 204800;
end if;

// signal exit on Unix
if not win then
  r = process.run('/bin/sh', ['-c', 'kill -TERM $$']);
  ?. r.ok = false;
  ?. r.exitCode = -15;
  ?. r.signal = 15;
else
  ?. true;
  ?. true;
  ?. true;
end if;

// nil args are accepted
if win then
  ?. true;
else
  r = process.run('/usr/bin/true', nil);
  ?. r.ok;
end if;

// unknown options are rejected
bad = false;
try
  process.run('x', [], [timout: 1]);
except
  bad = ('' & @).subpos('unknown option') >= 0;
end try;
?. bad;

// output cap stops a runaway producer
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'for /L %i in (1,1,20000) do @echo x'],
                  [output: 1024]);
else
  r = process.run('/bin/dd', ['if=/dev/zero', 'bs=1024', 'count=200'],
                  [output: 1024]);
end if;
?. r.ok = false;
?. r.outputExceeded;
?. r.stdout.length() <= 1024;

// output cap does not affect results below the limit
if win then
  r = process.run('cmd.exe', ['/d', '/c', 'echo ok'], [output: 1024]);
else
  r = process.run('/bin/echo', ['ok'], [output: 1024]);
end if;
?. r.ok;
?. r.outputExceeded = false;
?. r.stdout.length() < 1024;

// invalid output option
bad = false;
try
  process.run('x', [], [output: -1]);
except
  bad = ('' & @).subpos('output must be') >= 0;
end try;
?. bad;
