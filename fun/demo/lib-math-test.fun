
########################################
# test for lib-math.fun
########################################

use '..\lib\lib-math.fun';

test();

fun test()
  ?, 8    = pow(2, 3);
  ?, 2    = sqrt(4);
  ?, e()  = exp(1);
  ?, 2    = log(exp(2));
  ?, 3    = log2(pow(2, 3));
  ?. 4    = log10(pow(10, 4));

  ?, 0.000001 > abs(1 - sin(pi() / 6) * 2);
  ?, 0.000001 > abs(1 - cos(pi() / 3) * 2);
  ?, 0.000001 > abs(1 - tan(pi() / 4));
  ?, 0.000001 > abs(pi() - atan(sqrt(3)) * 3);
  ?, 0.000001 > abs(pi() - asin(sqrt(3) / 2) * 3);
  ?. 0.000001 > abs(pi() - acos(sqrt(3) / 2) * 6);

  ?, pi();
  ?. e();

  ?, 9 = max(1, 9);
  ?, 1 = min(1, 9);
  ?, 1 = abs(-1);
  ?, 1 = round(1.4);
  ?, 1 = round(1.4999);
  ?. 2 = round(1.5);

  randomize();
  ?, random() < 1;
  ?, random() < 1;
  ?, random() < 1;
  ?, randomint(100) < 100;
  ?, randomint(100) < 100;
  ?. randomint(100) < 100;
end fun;
