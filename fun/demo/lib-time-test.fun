
########################################
# test for lib-time.fun
########################################

use '..\lib\lib-time.fun';

test();

fun test()
  ?. date();
  ?. time();

  var t = tick(-2);
  var s = 0;
  for i = 1 to 1000000 do
    s += i;
  end do;
  ?, s;
  ?. t.get();
end fun;
