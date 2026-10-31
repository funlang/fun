// io: raw stdout bytes; compared byte-for-byte on every platform.
use 'fun/lib/io.fun';
io.stdout().write('io-stdio-out' & 10.toChar());
