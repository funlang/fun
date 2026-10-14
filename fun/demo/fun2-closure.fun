
########################################
# functional-closure
########################################

fun counter()
  var i = 0;
  return fun(){
    i += 1;
    result = i;
  };
end fun;

var c = counter();
?. c();
?. c();
?. c();

fun mul(bas)
  return fun(times){
    return bas * times;
  };
end fun;

var m = mul(3);
?. m(4);
?. m(5);
?. m(6);
