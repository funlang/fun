// Regression pin for the scalar fast paths in src/core/base.pas and
// src/core/calc.inc: Boolean results, Double/Boolean assignment, and the
// guarded integer div/mod paths.

// Boolean result replacing a managed value: the old string payload must be
// released, and the result must be a real Boolean.
var x = 'abc';
x = (1 > 2);
?. x;                        // False

// Boolean -> double -> Boolean on the same variable.
var d = (1 < 2);
d = 7.25;
?. d;                        // 7.25
d = 3;
d = (2 <= 2);
?. d;                        // True

// Scalar copies through assignment and through a function boundary.
var b = (1 = 1);
var b2 = b;
?. b2;                       // True
b2 = not b2;
?. b2;                       // False

var o = new [v: 1 > 2];
?. o.v;                      // False
o.v = (2 < 3);
?. o.v;                      // True

fun take(v) result = v; end fun;
?. take(1 > 2);              // False
?. take(1 < 2);              // True
?. take(1.5 + 2.5);          // 4

// All Boolean-producing operators keep their truth values.
?. not (1 > 2);              // True
?. (1 < 2) or  (1 > 2);      // True
?. (1 > 2) and (1 < 2);      // False
?. (1 < 2) xor (1 > 2);      // True

// Integer div/mod, including negative operands and numeric strings.
var i1 = 7;
var i2 = 3;
?. 7 div 3;                  // 2
?. i1 div i2;                // 2
?. -7 div 3;                 // -2
?. -7 mod 3;                 // -1
?. 7 div -3;                 // -2
?. 7 mod -3;                 // 1
?. 7 div '2';                // 3
?. 7 mod '2';                // 1

// A zero divisor still raises (the fast paths fall through to the RTL).
fun raises(f)
  try
    f();
    result = false;
  except
    result = true;
  end try;
end fun;

?. raises({var z = 7 div 0;});   // True
?. raises({var z = 7 mod 0;});   // True

// Low(Integer) div/mod -1 may return or raise depending on the Variant RTL;
// either way the value must not be silently wrong.
var mn = 0 - 2147483647 - 1;
var lowdiv = false;
try
  var v = mn div -1;
  lowdiv = (v = mn);
except
  lowdiv = true;
end try;
?. lowdiv;                   // True

var lowmod = false;
try
  var v = mn mod -1;
  lowmod = (v = 0);
except
  lowmod = true;
end try;
?. lowmod;                   // True

// Integer comparison at the int32 boundaries. The fast paths used to compute
// a - b and test its sign; that difference overflows and reverses the result
// for far-apart operands. All six relational operators must compare directly.
?. 2147483647 > -1;          // True
?. -2147483648 < 1;          // True
?. 2147483647 > -2147483648; // True
?. -2147483648 > 2147483647; // False
?. 2147483647 >= -1;         // True
?. 2147483647 <= -1;         // False
?. -2147483648 >= 1;         // False
?. -2147483648 <= 1;         // True
?. 2147483647 <> -1;         // True
?. 2147483647 = -1;          // False
