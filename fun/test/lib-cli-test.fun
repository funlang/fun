// cli: command/flag parsing, help and exit codes. The snapshot contains
// booleans only.
use 'fun/lib/io.fun';
use 'fun/lib/cli.fun';
use 'fun/lib/env.fun';

var got = new [];
var beforeCount = 0;
var afterCount = 0;
var parentBefore = 0;
var parentAfter = 0;
var parentCmd = '';
var parentSeen = '';
var parentHas = false;
var nestedTrace = '';

fun _count(xs)
  if xs = nil then result = 0; else result = xs.@count(); end if;
end fun;

fun main(ctx)
  got.@add(ctx.string('name'));
  got.@add(ctx.int('times'));
  got.@add(ctx.float('ratio'));
  got.@add(ctx.bool('verbose'));
  got.@add(_count(ctx.strings('tag')));
  got.@add(ctx.narg());
  got.@add(ctx.arg(0));
  got.@add(ctx.has('name'));
  got.@add(ctx.has('verbose'));
  got.@add(ctx.command());
end fun;

fun serve(ctx)
  got.@add(ctx.string('name'));
  got.@add(ctx.int('port'));
  got.@add(ctx.narg());
  got.@add(ctx.command());
end fun;

fun addBefore(ctx)
  beforeCount += 1;
end fun;

fun rejectBefore(ctx)
  beforeCount += 1;
  result = false;
end fun;

fun addAfter(ctx)
  afterCount += 1;
end fun;

fun returnsSeven(ctx)
  result = 7;
end fun;

fun returnsFive(ctx)
  result = 5;
end fun;

fun returnsFalse(ctx)
  result = false;
end fun;

fun returnsTrue(ctx)
  result = true;
end fun;

fun afterRaises(ctx)
  raise 'after boom';
end fun;

fun afterReturns(ctx)
  result = 7;
end fun;

fun raises(ctx)
  raise 'boom';
end fun;

fun parentBeforeHook(ctx)
  parentBefore += 1;
  parentCmd = ctx.command();
end fun;

fun parentAfterHook(ctx)
  parentAfter += 1;
end fun;

fun runParentChild(ctx)
  parentSeen = ctx.string('name') & ':' & ctx.int('port');
  parentHas = ctx.has('name');
end fun;

fun ghostAction(ctx)
  got.@add(ctx.command());
end fun;

fun tagAction(ctx)
  var xs = ctx.strings('tag');
  got.@add(xs.@count());
  xs.@add('mutated');
end fun;

fun leafAction(ctx)
  got.@add(ctx.command());
  got.@add(ctx.int('level'));
end fun;

fun reqAction(ctx)
  got.@add(ctx.string('x'));
end fun;

fun sameAction(ctx)
  got.@add(ctx.int('port'));
  got.@add(ctx.has('port'));
end fun;

fun leafHelpAction(ctx)
  got.@add(ctx.narg());
  got.@add(ctx.arg(0));
end fun;

fun badAfterAction(ctx)
  raise 'after action boom';
end fun;

fun ctxOutAction(ctx)
  ctx.out().write('ctx-out');
  ctx.err().write('ctx-err');
end fun;

fun writerBefore(ctx)
  ctx.out().write('P');
end fun;

fun writerAfter(ctx)
  ctx.out().write('A');
end fun;

fun writerAction(ctx)
  ctx.out().write('C');
end fun;

fun rootNameAction(ctx)
  got.@add(ctx.string('name'));
end fun;

fun returnsText(ctx)
  result = 'text';
end fun;

fun beforeText(ctx)
  result = 'text';
end fun;

fun nestedBefore(ctx)
  nestedTrace &= 'B' & ctx.command() & ';';
end fun;

fun nestedAfter(ctx)
  nestedTrace &= 'A' & ctx.command() & ';';
end fun;

fun nestedAction(ctx)
  nestedTrace &= 'X;';
end fun;

fun badContext(ctx)
  ctx.int('nope');
end fun;

fun wrongContext(ctx)
  ctx.int('name');
end fun;

fun badHas(ctx)
  ctx.has('nope');
end fun;

fun _newApp()
  var o = io.buffer();
  var e = io.buffer();
  result = new [];
  result.@add(cli.command('demo', [version: '1.2.3', out: o, err: e]));
  result.@add(o);
  result.@add(e);
end fun;

var a = _newApp();
var root = a[0];
var out = a[1];
var err = a[2];
root.flag(cli.string('name', [aliases: ['n'], value: 'world']));
root.flag(cli.bool('verbose', [aliases: ['V']]));
root.flag(cli.int('times', [aliases: ['t'], value: 1]));
root.flag(cli.float('ratio', [aliases: ['r'], value: 1.5]));
root.flag(cli.strings('tag', [aliases: ['T']]));
root.flag(cli.string('secret', [hidden: true]));
root.action(main);
var serveCmd = cli.command('serve', [
  aliases: ['s'],
  usage: 'serve things',
  flags: [cli.int('port', [aliases: ['p'], value: 80])],
  action: serve
]);
root.command(serveCmd);
var ghostCmd = cli.command('ghost', [
  aliases: ['g'],
  hidden: true,
  action: ghostAction
]);
root.command(ghostCmd);

got = new [];
?. root.run(['--name', 'bob', '-V', '-t', '3', '-r', '2.5', '-T', 'a', '--tag=b', '--', 'x', 'y']) = 0;
?. got[0] = 'bob';
?. got[1] = 3;
?. got[2] = 2.5;
?. got[3] = true;
?. got[4] = 2;
?. got[5] = 2;
?. got[6] = 'x';
?. got[7] = true;
?. got[8] = true;
?. got[9] = 'demo';

got = new [];
?. root.run(['s', '-p', '8080', 'z']) = 0;
?. got[0] = 'world';
?. got[1] = 8080;
?. got[2] = 1;
?. got[3] = 'serve';

got = new [];
?. root.run(['--', '-x', 'y']) = 0;
?. got[0] = 'world';
?. got[5] = 2;
?. got[6] = '-x';

got = new [];
?. root.run(['--verbose=false']) = 0;
?. got[3] = false;
got = new [];
?. root.run(['--verbose=true']) = 0;
?. got[3] = true;

// help must not fail on an invalid env value
env.set('CLI_HELP_BAD', 'abc');
var helpEnv = cli.command('help-env', [out: out, err: err]);
helpEnv.flag(cli.int('n', [env: 'CLI_HELP_BAD']));
out.reset();
err.reset();
?. helpEnv.run(['help']) = 0;
?. err.text() = '';
out.reset();
?. helpEnv.run(['--help']) = 0;
env.unset('CLI_HELP_BAD');

// help / version / command help / help command
out.reset();
?. root.run(['--help']) = 0;
?. out.text().subpos('usage: demo') >= 0;
?. out.text().subpos('serve (s)') >= 0;
?. out.text().subpos('serve things') >= 0;
?. out.text().subpos('-n, --name') >= 0;
?. out.text().subpos('(default: "world")') >= 0;
?. out.text().subpos('(default: 1)') >= 0;
?. out.text().subpos('secret') < 0;
?. out.text().subpos('ghost') < 0;
out.reset();
?. root.run(['--version']) = 0;
?. out.text().subpos('1.2.3') >= 0;
out.reset();
?. root.run(['-v']) = 0;
?. out.text().subpos('1.2.3') >= 0;
out.reset();
got = new [];
?. root.run(['-V']) = 0;
?. out.text() = '';
?. got[3] = true;
got = new [];
?. root.run(['g']) = 0;
?. got[0] = 'ghost';
got = new [];
?. root.run(['--secret', 'x']) = 0;
?. got[0] = 'world';
out.reset();
?. root.run(['serve', '--help']) = 0;
?. out.text().subpos('usage: serve') >= 0;
?. out.text().subpos('serve things') >= 0;
?. out.text().subpos('(default: 80)') >= 0;
out.reset();
?. root.run(['help', 'serve']) = 0;
?. out.text().subpos('usage: serve') >= 0;
out.reset();
?. root.run(['help']) = 0;
?. out.text().subpos('usage: demo') >= 0;
out.reset();
?. root.run(['help', 'help']) = 0;
?. out.text().subpos('usage: demo') >= 0;
var verCmd = cli.command('ver', [out: out, err: err, version: '2.0']);
out.reset();
?. verCmd.run(['--version']) = 0;
?. out.text().subpos('ver 2.0') >= 0;
var meta = cli.command('meta', [
  out: out,
  err: err,
  description: 'meta description',
  usageText: 'usage: meta CUSTOM'
]);
out.reset();
?. meta.run(['--help']) = 0;
?. out.text().subpos('meta description') >= 0;
?. out.text().subpos('usage: meta CUSTOM') >= 0;
var argsc = cli.command('argsc', [out: out, err: err, argsUsage: 'FILE...']);
argsc.flag(cli.bool('toggle', [value: false]));
argsc.flag(cli.strings('tag', [value: ['a', 'b']]));
out.reset();
?. argsc.run(['--help']) = 0;
?. out.text().subpos('usage: argsc [options] FILE...') >= 0;
?. out.text().subpos('(default: false)') >= 0;
?. out.text().subpos('(default: ["a","b"])') >= 0;

// unknown command/flag and conversion errors
err.reset();
?. root.run(['nope']) = 2;
?. err.text().subpos('unknown command') >= 0;
err.reset();
?. root.run(['--bad']) = 2;
?. err.text().subpos('unknown flag') >= 0;
err.reset();
?. root.run(['--name']) = 2;
?. err.text().subpos('needs a value') >= 0;
err.reset();
?. root.run(['--times', 'x']) = 2;
?. err.text().subpos('invalid integer') >= 0;
?. err.text().subpos('--times') >= 0;
err.reset();
?. root.run(['--name', '--help']) = 2;
?. err.text().subpos('needs a value') >= 0;
err.reset();
?. root.run(['-T', '-V']) = 2;
?. err.text().subpos('needs a value') >= 0;
got = new [];
?. root.run(['--name=-x']) = 0;
?. got[0] = '-x';
got = new [];
?. root.run(['--times', '-1', '--ratio', '-.5']) = 0;
?. got[1] = -1;
?. got[2] = -0.5;
err.reset();
?. root.run(['--ratio', 'x']) = 2;
?. err.text().subpos('invalid number') >= 0;
err.reset();
?. root.run(['serve', '--bad']) = 2;
?. err.text().subpos('unknown flag') >= 0;
err.reset();
?. root.run(['serve', '--name', 'x']) = 2;
?. err.text().subpos('unknown flag') >= 0;
err.reset();
?. root.run(['help', 'nope']) = 2;
?. err.text().subpos('unknown command') >= 0;

// required
var r = cli.command('req', [out: out, err: err]);
r.flag(cli.string('x', [required: true]));
r.action(reqAction);
err.reset();
?. r.run([]) = 2;
?. err.text().subpos('required flag') >= 0;
got = new [];
?. r.run(['--x=', 'a']) = 0;
?. got[0] = '';

// env fallback
env.set('CLI_TEST_NAME', 'from-env');
env.set('CLI_TEST_TIMES', '9');
env.set('CLI_TEST_TAGS', 'a,b');
env.set('CLI_TEST_VERBOSE', 'true');
var eapp = cli.command('env', [out: out, err: err]);
eapp.flag(cli.string('name', [env: 'CLI_TEST_NAME']));
eapp.flag(cli.int('times', [env: 'CLI_TEST_TIMES']));
eapp.flag(cli.strings('tag', [env: 'CLI_TEST_TAGS']));
eapp.flag(cli.bool('verbose', [env: 'CLI_TEST_VERBOSE']));
eapp.flag(cli.float('ratio', [value: 1.5]));
eapp.action(main);
got = new [];
?. eapp.run([]) = 0;
?. got[0] = 'from-env';
?. got[1] = 9;
?. got[3] = true;
?. got[4] = 2;
?. got[7] = true;
?. got[8] = true;
env.set('CLI_TEST_TAGS', '');
got = new [];
?. eapp.run([]) = 0;
?. got[4] = 0;
env.set('CLI_TEST_TIMES', 'bad');
err.reset();
?. eapp.run([]) = 2;
?. err.text().subpos('from env CLI_TEST_TIMES') >= 0;
env.unset('CLI_TEST_NAME');
env.unset('CLI_TEST_TIMES');
env.unset('CLI_TEST_TAGS');
env.unset('CLI_TEST_VERBOSE');

// before/after via constructor options
var optHooks = cli.command('opt-hooks', [
  out: out,
  err: err,
  before: addBefore,
  after: addAfter,
  action: returnsSeven
]);
beforeCount = 0;
afterCount = 0;
?. optHooks.run([]) = 7;
?. beforeCount = 1;
?. afterCount = 1;

// before/after and exit code
var h = cli.command('hooks', [out: out, err: err]);
h.flag(cli.string('name', [value: 'x']));
h.before(addBefore);
h.after(addAfter);
h.action(returnsSeven);
beforeCount = 0;
afterCount = 0;
?. h.run([]) = 7;
?. beforeCount = 1;
?. afterCount = 1;
var stop = cli.command('stop', [out: out, err: err]);
stop.before(rejectBefore);
stop.action(main);
beforeCount = 0;
?. stop.run([]) = 1;
?. beforeCount = 1;

// parent hooks wrap subcommands; help does not run hooks
var pr = cli.command('parent', [out: out, err: err]);
pr.flag(cli.string('name', [value: 'p']));
pr.before(parentBeforeHook);
pr.after(parentAfterHook);
pr.command(cli.command('child', [
  flags: [cli.int('port', [aliases: ['p'], value: 80])],
  action: runParentChild
]));
parentBefore = 0;
parentAfter = 0;
parentCmd = '';
parentSeen = '';
parentHas = false;
?. pr.run(['child', '--port', '9']) = 0;
?. parentBefore = 1;
?. parentAfter = 1;
?. parentCmd = 'parent';
?. parentSeen = 'p:9';
?. parentHas = false;
parentSeen = '';
parentHas = false;
?. pr.run(['--name', 'z', 'child', '--port', '9']) = 0;
?. parentSeen = 'z:9';
?. parentHas = true;
parentBefore = 0;
parentAfter = 0;
out.reset();
?. pr.run(['--help']) = 0;
?. parentBefore = 0;
?. parentAfter = 0;
parentBefore = 0;
parentAfter = 0;
out.reset();
?. pr.run(['child', '--help']) = 0;
?. parentBefore = 0;
?. parentAfter = 0;
parentBefore = 0;
parentAfter = 0;
err.reset();
?. pr.run(['child', '--bad']) = 2;
?. parentBefore = 0;
?. parentAfter = 0;

var reqRoot = cli.command('req-root', [out: out, err: err]);
reqRoot.flag(cli.string('token', [required: true]));
reqRoot.command(cli.command('child', [action: leafHelpAction]));
err.reset();
?. reqRoot.run(['child', '--help']) = 0;
?. err.text() = '';
err.reset();
?. reqRoot.run(['child']) = 2;
?. err.text().subpos('required flag --token') >= 0;

env.set('CLI_ROOT_NAME', 'root-env');
var envRoot = cli.command('env-root', [out: out, err: err]);
envRoot.flag(cli.string('name', [env: 'CLI_ROOT_NAME']));
envRoot.command(cli.command('child', [out: out, err: err, action: rootNameAction]));
got = new [];
?. envRoot.run(['child']) = 0;
?. got[0] = 'root-env';
env.unset('CLI_ROOT_NAME');

var parentErr = cli.command('parent-err', [out: out, err: err]);
parentErr.before(parentBeforeHook);
parentErr.after(parentAfterHook);
parentErr.command(cli.command('child', [action: raises]));
parentBefore = 0;
parentAfter = 0;
err.reset();
?. parentErr.run(['child']) = 1;
?. parentBefore = 1;
?. parentAfter = 1;

var stopParent = cli.command('stop-parent', [out: out, err: err]);
stopParent.before(rejectBefore);
stopParent.command(cli.command('child', [action: ghostAction]));
beforeCount = 0;
got = new [];
?. stopParent.run(['child']) = 1;
?. beforeCount = 1;
?. got.@count() = 0;

// a required flag is not satisfied by its default
var reqd = cli.command('required-default', [out: out, err: err]);
reqd.flag(cli.string('x', [required: true, value: 'd']));
reqd.action(main);
got = new [];
?. reqd.run([]) = 2;
?. got.@count() = 0;

// a child's own writers override the root's
var cOut = io.buffer();
var cErr = io.buffer();
var p2 = cli.command('p2', [out: out, err: err]);
p2.command(cli.command('c', [out: cOut, err: cErr]));
out.reset();
?. p2.run(['c', '--help']) = 0;
?. cOut.text().subpos('usage: c') >= 0;
?. out.text() = '';

// child flags with a parent's name use the child's own default
var sameRoot = cli.command('same', [out: out, err: err]);
sameRoot.flag(cli.int('port', [value: 80]));
sameRoot.command(cli.command('child', [
  out: out,
  err: err,
  flags: [cli.int('port', [value: 8080])],
  action: sameAction
]));
got = new [];
?. sameRoot.run(['child']) = 0;
?. got[0] = 8080;
?. got[1] = false;
got = new [];
?. sameRoot.run(['--port', '90', 'child']) = 0;
?. got[0] = 90;
?. got[1] = true;

// a leaf command can use help as a positional value
var leafHelp = cli.command('leaf-help', [out: out, err: err, action: leafHelpAction]);
root.command(leafHelp);
got = new [];
?. root.run(['leaf-help', 'help']) = 0;
?. got[0] = 1;
?. got[1] = 'help';

// contexts expose the selected writers
var ctxOut = io.buffer();
var ctxErr = io.buffer();
var ctxCmd = cli.command('ctx-out', [out: ctxOut, err: ctxErr, action: ctxOutAction]);
?. ctxCmd.run([]) = 0;
?. ctxOut.text() = 'ctx-out';
?. ctxErr.text() = 'ctx-err';

// parent and child contexts use their own selected writers
var writerRoot = io.buffer();
var writerChild = io.buffer();
var writerParent = cli.command('writer-parent', [out: writerRoot, err: writerRoot]);
writerParent.before(writerBefore);
writerParent.after(writerAfter);
writerParent.command(cli.command('child', [
  out: writerChild,
  err: writerChild,
  action: writerAction
]));
?. writerParent.run(['child']) = 0;
?. writerRoot.text() = 'PA';
?. writerChild.text() = 'C';

// after hooks run when an action raises
var afterErr = cli.command('after-err', [out: out, err: err]);
afterErr.after(addAfter);
afterErr.action(badAfterAction);
afterCount = 0;
err.reset();
?. afterErr.run([]) = 1;
?. afterCount = 1;
?. err.text().subpos('after action boom') >= 0;

// default slices are copied for each run and are not shared with the action
var ds = cli.command('defaults', [out: out, err: err]);
ds.flag(cli.strings('tag', [value: ['base']]));
ds.action(tagAction);
got = new [];
?. ds.run([]) = 0;
?. ds.run([]) = 0;
?. got[0] = 1;
?. got[1] = 1;

// nested commands and commands: option
var top = cli.command('top', [out: out, err: err]);
var leaf = cli.command('leaf', [
  flags: [cli.int('level', [aliases: ['l'], value: 1])],
  action: leafAction
]);
var mid = cli.command('mid', [out: out, err: err, commands: [leaf]]);
top.command(mid);
got = new [];
?. top.run(['mid', 'leaf', '-l', '5']) = 0;
?. got[0] = 'leaf';
?. got[1] = 5;
out.reset();
?. top.run(['help', 'mid', 'leaf']) = 0;
?. out.text().subpos('usage: leaf') >= 0;

// action and hook return values map to exit codes
var five = cli.command('five', [out: out, err: err]);
five.before(returnsFive);
five.action(main);
got = new [];
?. five.run([]) = 5;
?. got.@count() = 0;
var falseAction = cli.command('false-action', [out: out, err: err]);
falseAction.action(returnsFalse);
?. falseAction.run([]) = 1;
var trueAction = cli.command('true-action', [out: out, err: err]);
trueAction.action(returnsTrue);
?. trueAction.run([]) = 0;
var afterBad = cli.command('after-bad', [out: out, err: err]);
afterBad.after(afterRaises);
afterBad.action(returnsSeven);
err.reset();
?. afterBad.run([]) = 1;
?. err.text().subpos('error: after boom') >= 0;
var afterSeven = cli.command('after-seven', [out: out, err: err]);
afterSeven.after(afterReturns);
afterSeven.action(returnsSeven);
?. afterSeven.run([]) = 7;

// typed context accessors reject typos and wrong types
var badCtx = cli.command('bad-context', [out: out, err: err]);
badCtx.flag(cli.string('name'));
badCtx.action(badContext);
err.reset();
?. badCtx.run([]) = 1;
?. err.text().subpos("unknown flag 'nope'") >= 0;
var wrongCtx = cli.command('wrong-context', [out: out, err: err]);
wrongCtx.flag(cli.string('name'));
wrongCtx.action(wrongContext);
err.reset();
?. wrongCtx.run([]) = 1;
?. err.text().subpos('is string, not int') >= 0;
var badHasCmd = cli.command('bad-has', [out: out, err: err]);
badHasCmd.flag(cli.string('name'));
badHasCmd.action(badHas);
err.reset();
?. badHasCmd.run([]) = 1;
?. err.text().subpos("unknown flag 'nope'") >= 0;

// nested parent hooks run outside-in, then unwind inside-out
var nTop = cli.command('n-top', [out: out, err: err]);
nTop.before(nestedBefore);
nTop.after(nestedAfter);
var nMid = cli.command('n-mid', [out: out, err: err]);
nMid.before(nestedBefore);
nMid.after(nestedAfter);
nMid.command(cli.command('n-leaf', [out: out, err: err, action: nestedAction]));
nTop.command(nMid);
nestedTrace = '';
?. nTop.run(['n-mid', 'n-leaf']) = 0;
?. nestedTrace = 'Bn-top;Bn-mid;X;An-mid;An-top;';

// unsupported action/before return types fail loudly
var textAction = cli.command('text-action', [out: out, err: err]);
textAction.action(returnsText);
err.reset();
?. textAction.run([]) = 1;
?. err.text().subpos('action must return') >= 0;
var textBefore = cli.command('text-before', [out: out, err: err]);
textBefore.before(beforeText);
textBefore.action(returnsSeven);
err.reset();
?. textBefore.run([]) = 1;
?. err.text().subpos('before hook must return') >= 0;

// duplicate and reserved registrations are rejected at construction
var dupFlag = false;
try
  var d = cli.command('dup-flag', [flags: [cli.string('x'), cli.string('x')]]);
except
  dupFlag = true;
end try;
?. dupFlag;
var dupAlias = false;
try
  var d = cli.command('dup-alias', [flags: [cli.string('x', [aliases: ['a']]), cli.string('y', [aliases: ['a']])]]);
except
  dupAlias = true;
end try;
?. dupAlias;
var dupCmd = false;
try
  var p = cli.command('dup-cmd');
  p.command(cli.command('same-child'));
  p.command(cli.command('same-child'));
except
  dupCmd = true;
end try;
?. dupCmd;
var reservedFlag = false;
try
  var p = cli.command('reserved-flag');
  p.flag(cli.bool('help'));
except
  reservedFlag = true;
end try;
?. reservedFlag;
var reservedVersion = false;
try
  var p = cli.command('reserved-version', [version: '1']);
  p.flag(cli.bool('verbose', [aliases: ['v']]));
except
  reservedVersion = true;
end try;
?. reservedVersion;
var reservedCmd = false;
try
  var p = cli.command('reserved-cmd');
  p.command(cli.command('help'));
except
  reservedCmd = true;
end try;
?. reservedCmd;

// action exception becomes exit code 1
var bad = cli.command('bad', [out: out, err: err]);
bad.action(raises);
err.reset();
?. bad.run([]) = 1;
?. err.text().subpos('error: boom') >= 0;

// combined bool short flags
fun both(ctx)
  got.@add(ctx.bool('a'));
  got.@add(ctx.bool('b'));
end fun;
var combo = cli.command('combo', [out: out, err: err]);
combo.flag(cli.bool('a'));
combo.flag(cli.bool('b'));
combo.action(both);
got = new [];
?. combo.run(['-ab']) = 0;
?. got[0] = true;
?. got[1] = true;
