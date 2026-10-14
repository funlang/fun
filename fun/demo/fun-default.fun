
########################################
# fun-default
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

test(1, 2, 3);
test(1, 2);    # keep param(s) 'c' as null
test(1);       # keep param(s) 'b' and 'c' as null

########################################
# 1. Default arguments always be set as null
########################################
