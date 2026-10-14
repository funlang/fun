
########################################
# loop
########################################
#   loop
#     cmds
#   end loop;
########################################

var i = 1;

loop
  ?. i;
  exit;
end loop;

loop
  exit when i > 9;
  ? i;
  i += 1;
end loop;
?. '..DONE';

i = 9;

loop
  i -= 1;
  exit when i <= 0;
  next when i mod 2 = 1;
  ? i;
end loop;
?. '..DONE';

########################################
# 1. "exit" means exit the loop
#    "exit when" means when ... exit ...
#    "next" means skip to next loop
#    "next when" means when ... next ...
# 2. v += ... means v = v + ...
#    v -= ... means v = v - ...
#    v *= ... means v = v * ...
#    v &= ... means v = v & ...
########################################
