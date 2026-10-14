
########################################
# functional
########################################

fun foo(a)
  ?. 'Hello, ' & a & '!';
end fun;

var f = foo;
f('functional');

fun high(f, a)
  f(a);
end fun;

var h = high;
h(f, 'functional');
