
########################################
# loop-for-in
########################################
#   for v in expression loop
#     cmds
#   end loop;
########################################
#   for k : v in expression loop
#     cmds
#   end loop;
########################################
#   for k : v, i in expression loop
#     cmds
#   end loop;
########################################
#   for v, i in expression loop
#     cmds
#   end loop;
########################################

for i in [1, 2, 3, 4, 5] loop
  ? i;
end loop;
?. '..DONE';

for i in [5, 4, 3, 2, 1] do
  ? i;
end do;
?. '..DONE';

for k: i in [a: 1, b: 2, c: 3] do
  ?, k;
  ?, i;
end do;
?. 'DONE';

for k: i, j in [a: 1, b: 2, c: 3] do
  ?, k;
  ?, i;
  ?, j;
end do;
?. 'DONE';
