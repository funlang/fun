// Cross-format alignment: Fun numbers, JSON strict grammar, the built-in FD
// reader/writer, boolean coercion and duplicate keys.
//
// The BNF reader (`lib-fd.fun`) needs the regex engine, so its differential
// lives in fd-bnf-align.fun and is skipped on builds without regex.
//
// Run: fun/funcmd fun/test/data-align.fun

fun ok(cond, name)
  if cond then
    ?. 'PASS ' + name;
  else
    ?. 'FAIL ' + name;
  end if;
end fun;

fun jsonOk(s)
  try
    s.getJson(json: 2);
    result = true;
  except
    result = false;
  end try;
end fun;

fun fd(s)
  result = s.getJson(fd: true);
end fun;

var nl = 10.toChar();
var sl = 92.toChar();

// --- Fun integer literals no longer truncate to 32 bits --------------------
ok(2147483648 = 2147483648, 'literal > int32');
ok(9007199254740991 = 9007199254740991, 'literal 2^53-1');
ok(-9007199254740991 = -9007199254740991, 'negative literal 2^53-1');

// --- JSON strict: RFC 8259 numbers ----------------------------------------
ok(jsonOk('0'), 'strict 0');
ok(jsonOk('-0'), 'strict -0');
ok(jsonOk('0.5'), 'strict 0.5');
ok(jsonOk('1e+5'), 'strict 1e+5');
ok(jsonOk('-1.25E-3'), 'strict -1.25E-3');
ok(not jsonOk('.5'), 'strict rejects .5');
ok(not jsonOk('03'), 'strict rejects 03');
ok(not jsonOk('1.'), 'strict rejects 1.');
ok(not jsonOk('1e'), 'strict rejects 1e');
ok(not jsonOk('1e+'), 'strict rejects 1e+');
ok(not jsonOk('--1'), 'strict rejects --1');
ok(not jsonOk('1.2.3'), 'strict rejects 1.2.3');
ok(not jsonOk('9223372036854775808'), 'strict rejects int64 overflow');
// lenient keeps the historical superset
ok('.5'.getJson(json: true).@toJson() = '[0.5]', 'lenient .5');
ok('03'.getJson(json: true).@toJson() = '[3]', 'lenient 03');

// --- FD numbers follow fd.bnf.fd ------------------------------------------
ok(fd('n 03').n = 3, 'fd 03 is number');
ok(fd('n 03').n.type() = 3, 'fd 03 type int');
ok(fd('n 1.').n = '1.', 'fd 1. is string');
ok(fd('n .5').n = '.5', 'fd .5 is string');
ok(fd('n 0x10').n = '0x10', 'fd 0x10 is string');
ok(fd('n +1').n = '+1', 'fd +1 is string');
ok(fd('n 1e').n = '1e', 'fd 1e is string');
ok(fd('n 1.2.3').n = '1.2.3', 'fd 1.2.3 is string');
ok(fd('n true').n = true, 'fd true is bool');
ok(fd('n false').n = false, 'fd false is bool');
ok(fd('n null').n = nil, 'fd null');
ok(fd('n yes').n = 'yes', 'fd yes is string');
ok(fd('n no').n = 'no', 'fd no is string');

// safe integer boundary, equal in Fun / Pascal / JS
ok(fd('n 9007199254740991').n = 9007199254740991, 'fd safe int is number');
ok(fd('n 9007199254740992').n = '9007199254740992', 'fd 2^53 is string');
ok(fd('n 9223372036854775807').n = '9223372036854775807', 'fd int64 max is string');
ok(fd('n 1e309').n = '1e309', 'fd float overflow is string');

// --- FD escapes: only \"... enables them, like Fun esc() ------------------
var q = sl + '"';
ok(fd('n ' + q + 'a' + sl + 'nb"').n = 'a' + nl + 'b', 'fd backslash-n');
ok(fd('n ' + q + 'a' + sl + 'x41b"').n = 'aAb', 'fd backslash-x41');
ok(fd('n ' + q + 'a' + sl + 'qb"').n = 'a' + sl + 'qb', 'fd unknown escape');
ok(fd('n ' + q + 'a' + sl + 'vb"').n = 'a' + sl + 'vb', 'fd backslash-v stays literal');

// --- FD custom key/value delimiter ----------------------------------------
var kvd = '#!kvd:=' + nl + 'a=85' + nl + 'b=hello world' + nl;
ok(kvd.getJson(fd: true).a = 85, 'fd kvd number');
ok(kvd.getJson(fd: true).b = 'hello world', 'fd kvd string');

// --- duplicate named keys: last wins --------------------------------------
ok(fd('a 1' + nl + 'a 2').a = 2, 'fd duplicate key last wins');
ok('{"a":1,"a":2}'.getJson(json: true).a = 2, 'json duplicate key last wins');
ok(fd('a 1' + nl + 'a 2').@toJson() = '[a:2]', 'fd duplicate emits once');

// --- string truthiness is unchanged and scoped to Fun ---------------------
fun truth(s)
  if s then result = true; else result = false; end if;
end fun;
ok(truth('true') and truth('TRUE') and truth('yes'), 'bool true words');
ok(not truth('false') and not truth('no') and not truth(''), 'bool false words');
ok(not truth('0') and not truth('00') and not truth('-0'), 'bool numeric zero');
ok(not truth('0.0') and not truth('0e0') and truth('1e3'), 'bool numeric forms');
ok(truth('off') and truth(' no '), 'bool non-empty fallback');

// --- JSON writer escapes C0 controls --------------------------------------
ok((new [v: 11.toChar()]).@toJson(json: true) = '{"v":"' + sl + 'u000b"}', 'json \\u000b');
ok((new [v: 1.toChar()]).@toJson(json: true) = '{"v":"' + sl + 'u0001"}', 'json \\u0001');
