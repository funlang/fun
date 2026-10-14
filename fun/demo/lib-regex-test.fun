
########################################
# test for lib-regex.fun
########################################

use '..\lib\lib-regex.fun';

test();

fun test()
  # str.match(str), return bool
  ?,     'abcd123efg' =~ '123';
  ?,     'abcd123efg' !~ '1234';
  ?,     'abcd123efg' .match( '123' );
  ?. not 'abcd123efg' .match( '1234' );

  # str.match(reg), reg.match(str), return bool
  ?, not not 'abcd123efg' =~ /123/; # Convert to bool
  ?,         /1234/       !~ 'abcd123efg';
  ?, not not 'abcd123efg'    .match( /123/ );
  ?. not     '1234'.toRegex().match( 'abcd123efg' );

  # g, return list of matched string
  'abcd123efg'.match(/\d/g).@each((m){? '[' & m & ']'});
  ?. null;

  # not g, return match object
  ?. 'abcd123efg'.match(/\d+/).value();

  # str.match(reg, action), reg.match(str, action)
  # return string concated from return value of action
  ?. 'abcd123efg'.match(/\d/g, (m){@= '[' & m.value() & ']'});
  ?. 'abcd123efg'.match(/\d/i, (m){@= '[' & m.value() & ']'});

  # str.replace(str, newstr)
  ?. 'abcd123efg'.replace('123', '[123]');

  # str.replace(reg, newstr), reg.replace(str, newstr)
  ?. 'abcd123efg'.replace(/\d/g, '[$0]');

  # str.replace(reg, action), reg.replace(str, action)
  ?. 'abcd123efg'.replace(/\d/g, (m){@= '[' & m.value() * 3 & ']'});

  var right = '';
  var left  = splitonce(/\./, 'a.b', var right);
  ?. 'left: [$left], right: [$right]'.eval();

  split('a.b.c.d', /\./).@each((m){?, '[' & m & ']'});
  ?. null;
end fun;
