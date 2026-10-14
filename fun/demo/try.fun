
########################################
# try
########################################
#   try     cmds
# [ except  cmds ]                  0..1
# [ finally cmds ]                  0..1
#   end try;
########################################

try
  ? 'try..';     # HIT
except
  ? 'except..';
end try;
?. 'DONE';

try
  ? 'try..';     # HIT
finally
  ? 'finally..'; # HIT
end try;
?. 'DONE';

try
  ? 'try..';     # HIT
except
  ? 'except..';
finally
  ? 'finally..'; # HIT
end try;
?. 'DONE';

try
  ? 'try..';     # HIT
  ? 1 / 0;
  ? '1 / 0';
except
  ? 'except..';  # HIT
  ? @ & '..';    # HIT
finally
  ? 'finally..'; # HIT
end try;
?. 'DONE';

try
  ? 'try..';     # HIT
  raise "Stop!";
  ? 'Stop!';
except
  ? 'except..';  # HIT
  ? @ & '..';    # HIT
finally
  ? 'finally..'; # HIT
end try;
?. 'DONE';

########################################
# 1. "@" is a built-in variable in "except"
#        @ <- exception
# 2. "raise" can throw an exception
#        exception can be anything
########################################
