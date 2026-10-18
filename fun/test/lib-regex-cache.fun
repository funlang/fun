// Regression for the shared PCRE pattern cache: regex literals and
// toRegex() reuse a compiled pattern instead of recompiling on every call.
// Also pins the single-pass scan used by global match/replace.

fun show(k, v)
  ?. k & '=[' & v & ']';
end fun;

// repeated literal use: results must stay independent across calls
var i = 0;
var hits = 0;
while i < 50 loop
  if 'a1b22c333'.match(/\d+/g) <> nil then
    hits = hits + 1;
  end if;
  i = i + 1;
end loop;
show('repeat', hits);

show('replace1', 'a1b22c333'.replace(/\d+/g, '#'));
show('replace2', 'a12b345'.replace(/(\d)(\d+)/g, '$2$1'));

// same pattern text with different options must not share code
var sens  = 'AbC'.toRegex('');
var icase = 'AbC'.toRegex('i');
show('sens', sens.match('abc') <> nil);
show('icase', icase.match('abc') <> nil);
show('sensR', 'AbC'.replace(sens, 'x'));
show('icaseR', 'abc'.replace(icase, 'x'));

// dynamic pattern built per iteration
var s = '';
var j = 0;
while j < 5 loop
  var re = ('(x' & j & '?)').toRegex('g');
  s = s & '|' & 'axx'.replace(re, '{' & j & '}');
  j = j + 1;
end loop;
show('dyn', s);

// empty matches, anchors and callback replacements
show('empty', 'aXbXc'.replace(/X*/g, '-'));
show('anchor', 'abc'.replace(/^/g, '>'));
show('callback', 'x 1 y 22 z'.replace(/\d++/g, m->'<' & m.@@() & '>'));
show('shrink', 'a1b22c'.replace(/\d+/g, ''));
show('grow', 'a1b22c'.replace(/\d+/g, '0000'));

// global replacement computes $_ from the original subject
show('whole', 'abcabc'.replace(/b/g, '[$_]'));

// a lazy match object survives later use of the same literal
var re2 = /(\w+)-(\d+)/;
var m1 = re2.match('aa-11 bb-22');
show('m1a', m1.@@());
var m2 = re2.match('cc-33');
show('m2a', m2.@@());
show('m1next', m1.match());
show('m1b', m1.@@());
show('m2next', m2.match());
show('m2b', m2.@@());

// beyond one cache generation, a retained lazy match must still work
var keep = '(k\d+)'.toRegex('');
var km = keep.match('x k1 y k2');
show('keep1', km.@@());
var k = 0;
while k < 80 loop
  var r = ('(k' & k & '+)').toRegex('');
  r.match('k' & k);
  k = k + 1;
end loop;
show('keepNext', km.match());
show('keep2', km.@@());

show('ok', 'ok');
