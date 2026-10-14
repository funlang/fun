
########################################
# class-operators-override
########################################
#   this['+'] = fun (right) { ... }
#   this['-'] = fun (right) { ... }
#   ...
########################################

class Number(me)
  this['+'] = fun (you) {
    return me + you;
  };

  this['-'] = fun (you) {
    return me - you;
  };

  this['*'] = fun (you) {
    return me * you;
  };

  this['/'] = fun (you) {
    return me / you;
  };

  this['\'] = fun (you) {
    return me div you;
  };

  this['%'] = fun (you) {
    return me mod you;
  };

  this['^'] = fun (you) {
    return me ^ you;
  };

  this['='] = fun (you) {
    return me = you;
  };

  this['!'] = fun (you) {
    return me <> you;
  };

  this['>'] = fun (you) {
    return me > you;
  };

  this['<'] = fun (you) {
    return me < you;
  };
end class;

var n = Number(10);
?. n .+ 2;  // .+ means + override version
?. n .- 3;  // .- means - override version
?. n .* 4;  // .* means * override version
?. n ./ 5;  // ./ means / override version
?. n .\ 6;  // .\ means \ override version
?. n .% 7;  // .% means % override version
?. n .^ 8;  // .^ means ^ override version
?. n .> 9;  // .> means > override version
?. n .= 10; // .= means = override version
?. n .< 11; // .< means < override version
?. n .! 12; // .! means ! override version

########################################
# 1. Currently FUN supports override operators(16):
#    + - * / \ % ^ ! = < > & ~ ? | #
# 2. All override operators same precedence
# 3. All override operators are duality operators
#    So the functions will have one parameter
# 4. Must use "." append operators to use them
########################################
