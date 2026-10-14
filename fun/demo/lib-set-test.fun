
########################################
# test for lib-set.fun
########################################

use '..\lib\lib-set.fun';

test();

fun test()
  ?. [1, 2, 3].@count();

  [1, 2, 3].@each((i){?,i});
  ?. 'DONE';

  var abc = [a: 1, b: 2, c: 3];
  abc.@each((i, k){?,k & '=' & i});
  ?. 'DONE';

  abc.@add(4, 5, 6, g: 7, h: 8, i: 9)
     .@each((i, k){?,k & '=' & i});
  ?. 'DONE';
end fun;
