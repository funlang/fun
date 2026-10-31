// io: raw stderr bytes; compared byte-for-byte on every platform.
use 'fun/lib/io.fun';
io.stderr().write('io-stdio-err' & 10.toChar());
