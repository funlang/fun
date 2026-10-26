// env: public environment API. Values are never printed; only booleans are
// asserted, so the snapshot is host-neutral.
use 'fun/lib/env.fun';

var k = 'FUN_ENV_TEST_CORE';
env.unset(k);

?. env.has(k) = false;
?. env.get(k) = nil;
?. env.get(k, 'fallback') = 'fallback';

?. env.set(k, '') = true;
?. env.has(k) = true;
?. env.get(k).length() = 0;
?. env.get(k, 'fallback').length() = 0;

?. env.set(k, 'hello') = true;
?. env.get(k) = 'hello';
?. env.has(k) = true;

?. env.unset(k) = true;
?. env.has(k) = false;
?. env.get(k) = nil;
?. env.get(k, 'fallback') = 'fallback';

?. env.set('', 'x') = false;
?. env.set('A=B', 'x') = false;
?. env.set('A' & 0.toChar(), 'x') = false;
?. env.unset('') = false;
