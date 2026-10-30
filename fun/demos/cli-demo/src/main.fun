use '../../../lib/cli.fun';

fun hello(ctx)
  var times = ctx.int('times');
  var tags = ctx.strings('tag');
  for i = 1 to times do
    var line = 'hello ' & ctx.string('name');
    if tags.@count() > 0 then line &= ' tags=' & tags.@toJson(); end if;
    ?. line;
  end do;
end fun;

fun serve(ctx)
  ?. 'serving on port ' & ctx.int('port');
  if ctx.has('token') then ?. 'token accepted'; end if;
end fun;

fun noteBefore(ctx)
  if ctx.bool('verbose') then ?. 'before ' & ctx.command(); end if;
end fun;

fun noteAfter(ctx)
  if ctx.bool('verbose') then ?. 'after ' & ctx.command(); end if;
end fun;

var root = cli.command('cli-demo', [
  description: 'CLI framework walkthrough: commands, flags, aliases, env and hooks.',
  version: '0.1.0'
]);
root.flag(cli.string('name', [aliases: ['n'], value: 'world', usage: 'who to greet']));
root.flag(cli.bool('verbose', [aliases: ['V'], usage: 'trace hooks']));
root.flag(cli.int('times', [aliases: ['t'], value: 1, usage: 'repeat count']));
root.flag(cli.strings('tag', [aliases: ['T'], usage: 'add a tag (repeatable)']));
root.before(noteBefore);
root.after(noteAfter);
root.action(hello);
root.command(cli.command('serve', [
  usage: 'start a demo server',
  flags: [
    cli.int('port', [aliases: ['p'], value: 8080, env: 'CLI_DEMO_PORT', usage: 'listen port']),
    cli.string('token', [env: 'CLI_DEMO_TOKEN', usage: 'optional token'])
  ],
  action: serve
]));

var code = root.run();
if code <> 0 then cli.quit(code); end if;
