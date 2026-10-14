
########################################
# test for lib-dyns.fun
########################################

use '..\lib\lib-dyns.fun';

test();

fun test()
  // compile a file
  var a = 'lib-file-test.fun'.compile();
  a();      // execute lib-file-test.fun
  a.test(); // call test() in lib-file-test.fun

  // compile a string
  var b = '?. 1 + 2;'.compile();
  b();

  // compile a string inline
  var c = 'b();'.compile(inline: true);
  c();      // call b() in the current scope
end fun;
