
########################################
# test for lib-json.fun
########################################

use '..\lib\lib-json.fun';

test();

fun test()
  var s1 = '[1, 2, 3]'.getJson();
  s1.@each((i){?,i});
  ?. '';
  ?. s1.@toJson();

  var s2 = "[{key: str, val: 'this is a string.'},
             {key: num, val: 123456789}]".getJson();
  s2.@each(
    (i){
      i.@each(
        (v, k){
          ?, k & ': ' & v;
        }
      );
      ?. null;
    }
  );
  ?. 'format: 0';
  ?. s2.@toJson();
  ?. 'format: 1 level';
  ?. s2.@toJson(format: 1);
  ?. 'format: 2 levels';
  ?. s2.@toJson(format: 2);
end fun;
