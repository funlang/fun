
########################################
# scope
########################################

var a = 1;
var b = 2;
?. a = 1;
?. b = 2;

if true then
  var a = 2;  # new "a"
  b     = 22; # old "b"
  ?. a = 2;
  ?. b = 22;

  if true then
    var a = 3;  # new "a"
    b     = 33; # old "b"
    ?. a = 3;
    ?. b = 33;
  end if;

  ?. a = 2;
  ?. b = 33;
end if;

?. a = 1;
?. b = 33;
