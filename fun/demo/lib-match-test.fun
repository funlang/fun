
########################################
# test for lib-match.fun
########################################

use '..\lib\lib-match.fun';

test();

fun test()
  var m = 'a.b.c.d' =~ /\./;
  loop
    print(m.missed(), 'missed');
    print(m.value(), 'value');
    print(m.@@(), '@@');
    print(m.rest(), 'rest');
    ?. null;
    exit when not m.match();
  end loop;
  print(m.missed(), 'missed');
  ?. null;

  m = 'a.b.c' =~ /^(?P<first>\w)\.(\w)\.(\w)$/;
  print(m.gcount(), 'Count');
  print(m.groups('first'), 'first');
  ?. null;
  for i = 0 to m.gcount() - 1 do
    print(m.@(i), i);
  end do;
  ?. null;

  fun print(str, name)
    ?, '$name: [$str]'.eval();
  end fun;
end fun;
