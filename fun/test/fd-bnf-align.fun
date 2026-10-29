// Differential test: the BNF reference reader (lib-fd.fun) must produce the
// same tree as the built-in getJson(fd: true) reader.
//
// This test needs the regex engine, so run-windows-regression.bat lists it in
// REGEXTESTS and skips it when the Windows build has no PCRE.
//
// Run: fun/funcmd fun/test/fd-bnf-align.fun

use '../lib/lib-fd.fun' as fdlib;

fun ok(cond, name)
  if cond then
    ?. 'PASS ' + name;
  else
    ?. 'FAIL ' + name;
  end if;
end fun;

fun same(doc, name)
  try
    result = fdlib.parse(doc).@toJson() = doc.getJson(fd: true).@toJson();
  except
    result = false;
  end try;
  ok(result, name);
end fun;

var nl = 10.toChar();
var sl = 92.toChar();
var q = sl + '"';

var doc = 'a 85' + nl + 'b -3.14' + nl + 'c .5' + nl + 'd 0x10' + nl +
          'e 9007199254740992' + nl + 'f yes' + nl + 'g ' + q + 'x' + sl + 'x41"' + nl +
          'h 03' + nl + 'i 01' + nl + 'j 0.5' + nl + 'k 1e+3';
same(doc, 'BNF agrees on numbers/escapes');

var kvd = '#!kvd:=' + nl + 'a=85' + nl + 'b=hello world' + nl;
same(kvd, 'BNF agrees on kvd');

var ds = ['=', ';', ':', '|', ']'];
ds.@each((d){
  var x = '#!kvd:' + d + nl + 'a' + d + '85' + nl + 'b' + d + 'x y' + nl;
  same(x, 'BNF agrees on kvd ' + d);
});
