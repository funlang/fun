
########################################
# functional-mathematics and pipe
########################################
#   var name ( arguments ) = exp;
########################################
#   ( arguments ) -> exp
#   (           ) -> exp
#     argument    -> exp
#                 -> exp
########################################
#   a | b | c ...
########################################

var ifv = (condition, vtrue, vfalse){
  if condition then
    return vtrue;
  else
    return vfalse;
  end if;
};

var forto = (start, end1, step1, action){
  result = 0;
  for i = start to end1 step step1 do
    result = action(i, result);
  end do;
};

var sqrt(n)   = n ^ 0.5;

var max(a, b) = ifv(a > b, a, b);
var min(a, b) = ifv(a < b, a, b);

var sqrt2 = n -> n ^ 0.5;
var max2 = (a, b) -> ifv(a > b, a, b);
var min2 = (a, b) -> ifv(a < b, a, b);

var sum(s, e, i) = forto(s, e, i, (i, r) -> r + i);
var sum1(n)      = sum(1, n, 1);
var fact(n)      = forto(1, n, 1, (i, r) -> ifv(r=0, 1, r) * i);

?. sqrt(9);
?. max(1, 2);
?. min(1, 2);
?. sqrt2(9);
?. max2(1, 2);
?. min2(1, 2);
?. sum(1, 10000, 1);
?. sum1(10000);
?. fact(17);

var f = a -> a * 2;
var g = a -> a + 3;
?. g(f(1+2)+3);
?. 1+2|f+3|g;
