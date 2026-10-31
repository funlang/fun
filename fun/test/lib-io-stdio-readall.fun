// io: read all of process stdin; driven by lib-io-stdio-test.sh.
use 'fun/lib/io.fun';
io.stdout().write(io.readAll(io.stdin()));
