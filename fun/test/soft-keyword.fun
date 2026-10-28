// Reserved words are valid member names.
//
//   ./fun/funcmd fun/test/soft-keyword.fun
//
// This file intentionally uses reserved words after '.'.  Literal/named
// keys (`[fun: 1]`) are deliberately not covered.

// Build the object with quoted keys, then read them back as soft members.
var o = [
  'and': 1, 'as': 2, 'atom': 3, 'bit': 4, 'case': 5, 'class': 6, 'div': 7,
  'do': 8, 'else': 9, 'elsif': 10, 'end': 11, 'except': 12, 'exit': 13,
  'false': 14, 'finally': 15, 'for': 16, 'fun': 17, 'if': 18, 'in': 19,
  'is': 20, 'loop': 21, 'mod': 22, 'new': 23, 'next': 24, 'nil': 25,
  'not': 26, 'null': 27, 'or': 28, 'raise': 29, 'return': 30, 'step': 31,
  'then': 32, 'to': 33, 'true': 34, 'try': 35, 'use': 36, 'var': 37,
  'when': 38, 'while': 39, 'xor': 40
];

// All 40 reserved words work as member names.
?. o.and + o.as + o.atom + o.bit + o.case + o.class + o.div + o.do +
   o.else + o.elsif + o.end + o.except + o.exit + o.false + o.finally +
   o.for + o.fun + o.if + o.in + o.is + o.loop + o.mod + o.new + o.next +
   o.nil + o.not + o.null + o.or + o.raise + o.return + o.step + o.then +
   o.to + o.true + o.try + o.use + o.var + o.when + o.while + o.xor;

// Optional member access still works.
fun get(a)
  result = a?.fun?;
end fun;
?. get(['fun': 'ok']);
?. get(nil) = nil;

// `?.` remains the echo operator, not a member access.
?. not true;
?. bit not 0;

// `bit and` / `bit or` still form two-token operators.
?. 6 bit and 3;
?. 6 bit or 3;
