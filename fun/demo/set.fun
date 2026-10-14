
########################################
# set
########################################
#   [ value, value, value ... ]
########################################

var list = [0, 1, 2, 3, 4, 5];

?. 1 in list;
?. 3 in list;
?. 5 in list;
?. not 7 in list;

for i in list do
  ?, i;
end do;
?. 'DONE';

?. list[0];
?. list[1];
?. list[-1];
?. list[-2];

list[3]  = -3;
list[-1] = -5;

for i in list do
  ?, i;
end do;
?. 'DONE';

########################################
# 1. The elements can be anything includes base types and object types
#
#    [num: 1, str: "string", time: @'2010-04-23 17:26:22', bool: false]
#
#    [[name: 'fun', value: 'function'], [name: 'obj', value: 'object']]
#
# 2. Index of list start from 0 to N-1 and from -N to -1, as below:
#
#    var N = list.count();
#
#    [ 0   1   2   3    ...  N-3 N-2 N-1 ]
#      ------------>    ++1   --------->
#
#    [ 0-N 1-N 2-N 3-N  ...   -3  -2  -1 ]
#      <------------    --1   <---------
#
#    !!! Index must be Integer, Don't Use any Float or Double Index !!!
########################################
