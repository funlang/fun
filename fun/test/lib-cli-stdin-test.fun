// cli: ctx.stdin() defaults to process stdin.
use 'fun/lib/io.fun';
use 'fun/lib/cli.fun';

fun catIn(ctx)
  ctx.out().write(ctx.stdin().read(2));
  ctx.out().write(io.readAll(ctx.stdin()));
end fun;

var app = cli.command('cat', [action: catIn]);
var code = app.run([]);
if code <> 0 then cli.quit(code); end if;
