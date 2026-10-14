use 'lib-regex.fun';
use 'lib-set.fun';

class Number(me)
  this['#'] = you -> (me + you) * me * you;
end class;

var $ = Number(2);
?. $ .# 3;
?. $[1](3);

var f = a -> a * 2;
var g = a -> a + 3;
?. g(f(1+2)+3);
?. 1+2|f+3|g;

var q = 'a=1&b=2&c=&d=&e=..............';
var parseQuery = s -> (s | split(/&/) | map(sp_eq) | fromPairs);
?. parseQuery(q).@toJson(1);
