
########################################
# functional-currying
########################################
#   fun name ( arguments )
########################################

fun mul(bas, times)
  return bas * times;
end fun;

var m = fun mul(3);
?. m(4);
?. m(5);
?. m(6);
