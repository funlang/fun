// io: copy process stdin to stdout, including NUL and high bytes.
use 'fun/lib/io.fun';
io.copy(io.stdout(), io.stdin());
