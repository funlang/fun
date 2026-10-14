
########################################
# test for lib-string.fun
########################################

use '..\lib\lib-string.fun';

test();

fun test()
  var a = 'Www.FunLang.Org';

  ?. a.length();
  ?. a.lower();
  ?. a.upper();

  var b = a.lower();
  ?. b.subpos('fun');
  ?. b.substr();
  ?. b.substr(4);
  ?. b.substr(4, 7);
  ?. b.substr(len: 3);
  ?. b.substr(4, -8);
  ?. b.substr(-3);

  ?. a.substr(4, 7).x(3);

  var c = '[Hello\t\\\r\n\?\x40]';
  ?. c;
  ?. c.escape();

  var d = 'Error: %s at %s/%s.';
  ?. d;
  ?. d.format('"a" not found', 10, 3);

  var name = 'David';
  var e = 'Hello, $name.';
  ?. e;
  ?. e.eval();
end fun;
