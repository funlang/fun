
########################################
# test for lib-file.fun
########################################

use '..\lib\lib-file.fun';

test();

fun test()
  var f1 = 'c:\temp\admin\a.tmp';
  var f2 = 'c:\temp\admin\b.tmp';
  var f3 = 'c:\temp\admin\c.tmp';
  var fn = 'c:\temp\admin\?.tmp';

  f1.save('Hello, FUN.');
  ?. f1.load();

  f1.copy(f2, f3);
  ?. f2.load();
  ?. f3.load();

  use '..\lib\lib-base.fun';

  foreach(fn.find(), (f){?.f});

  f1.move();
  f2.move();
  f3.move();

  foreach(fn.find(), (f){?.f});
end fun;
