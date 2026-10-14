
########################################
# fun-ref
########################################

fun swap(a, b)
  var t = a;
  a = b;
  b = t;
end fun;

var i = 1;
var j = 9;
?. i & ' ' & j;

swap(i, j);         # Call by value
?. i & ' ' & j;

swap(var i, var j); # Call by reference
?. i & ' ' & j;

swap(var i, var j); # Call by reference
?. i & ' ' & j;

########################################
# 1. pass "var" arguments to call by reference
########################################
