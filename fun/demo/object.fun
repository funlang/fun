
########################################
# object
########################################

# number
?. (1.atan() * 2).sin();

# string
?. '123'.length();
?. 'abc'.upper();
?. 'ABC'.lower();

# set/list
?. [a: 1, b: 2, c: 3].a;

var s1 = [
  f1: fun(){
    ?. 'hello, f1';
  },
  f2: fun(){
    ?. 'hello, f2';
  }
];

s1.f1();
s1.f2();
