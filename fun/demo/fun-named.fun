
########################################
# fun-named
########################################
#   { name: value }                 0..n
########################################

# test define
fun test(a, b, c)
  # embed inner fun
  fun echo(name, str)
    ? name & '=[' & str & '] ';
  end fun;

  # echo the parameters
  echo('a', a);
  echo('b', b);
  echo('c', c);
  ?. 'DONE';
end fun;

test(a: 1, b: 2, c: 3);
test(c: 1, b: 2, a: 3);
test(c: 1, b: 2);       # keep param(s) 'a' as null
test(c: 1);             # keep param(s) 'b' and 'a' as null

########################################
# 1. Default arguments always be set as null
########################################
