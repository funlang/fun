
########################################
# use
########################################
#   use string;
########################################
#   use string as id;
########################################

?. '----Use fun-ref.fun ...';

use 'fun-ref.fun';

?. '----Used----';

i = 11;
j = 99;
?. i & ' ' & j;

swap(i, j);         # Call by value
?. i & ' ' & j;

swap(var i, var j); # Call by reference
?. i & ' ' & j;

swap(var i, var j); # Call by reference
?. i & ' ' & j;

use 'fun-ref.fun' as lib; # use as alias

i = 111;
j = 999;
?. i & ' ' & j;

lib.swap(var i, var j);   # use via module_alias.name
?. i & ' ' & j;

########################################
# 1. The used file will be inited at first (Run Once)
# 2. Can access the IDs for top level of the used file
#      Variables and functions/classes and so on
# 3. The latest IDs are valid for same name
#      Multiple files be used
# 4. Can re-name the module as a new id, such as
#      use "..." as newone;
#      ?. newone.test();
# 5. Files Can be used in anywhere
########################################
