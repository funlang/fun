# cli-demo

A small command-line program built with `cli.command`: global flags, aliases,
repeatable string flags, env fallback, parent hooks, help/version and a
subcommand.

```fun
var root = cli.command('cli-demo', [version: '0.1.0']);
root.flag(cli.string('name', [aliases: ['n'], value: 'world']));
root.action(hello);
root.command(cli.command('serve', [
  flags: [cli.int('port', [aliases: ['p'], value: 8080, env: 'CLI_DEMO_PORT'])],
  action: serve
]));
```

Run from this directory with the in-tree interpreter:

```text
../../../src/prj/fun/funcmd src/main.fun --help
../../../src/prj/fun/funcmd src/main.fun --name bob -t 2 -T fun -T cli
../../../src/prj/fun/funcmd src/main.fun -V serve -p 9000
CLI_DEMO_PORT=9100 CLI_DEMO_TOKEN=secret \
  ../../../src/prj/fun/funcmd src/main.fun serve
```

Use `--version` for the version, `help serve` for subcommand help, and put
global flags such as `-V` before `serve`. The demo only prints output; it does
not create files.
