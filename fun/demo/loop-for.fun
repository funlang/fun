
########################################
# loop-for
########################################
#   for v = e1 to e2 [step e3] loop
#     cmds
#   end loop;
########################################

for i = 1 to 9 loop
  ? i;
end loop;
?. '..DONE';

for i = 9 to 1 step -1 do
  ? i;
end do;
?. '..DONE';

########################################
# 1. for ... "loop" -> for ... "do"
#    end     "loop" -> end     "do"
# 2. v is a built-in variable in loop
########################################
