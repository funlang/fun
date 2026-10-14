
########################################
# fun
########################################
#   fun name ( parameters )
#     cmds
#   end fun;
########################################

# Define a function named "foo"
fun foo()
  ?. 'Hello, fun!';
end fun;

# Call function "foo"
foo();

# Define a function with parameters
fun max(a, b)
  if a > b then
    result = a;
  else
    result = b;
  end if;
end fun;

fun min(a, b)
  if a < b then
    return a;
  else
    return b;
  end if;
end fun;

?. max(1, 9);
?. max(9, 1);
?. min(1, 9);
?. min(9, 1);

########################################
# 1. "result", "@" are built-in variables in "fun"
#        they all be defined as the result value of the fun
# 2. "return" means return the fun
#        it can return with/without a value
# 3. "exit" can exit a fun too
########################################
