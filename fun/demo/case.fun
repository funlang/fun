
########################################
# case
########################################
#   case expression is
#   { when value do cmds }+         1..n
#   [ else          cmds ]          0..1
#   end case;
########################################

var exp = 1;

case exp is
  when 1 do
    ?. 1; # HIT
  when 2 do
    ?. 2;
  when 3 do
    ?. 3;
  else
    ?. 'else';
end case;

exp = "Hello";

case exp is
  when "Good" do
    ?. @ & ' morning!';
  when "Bad" do
    ?. @ & ' command or file name!';
  when "Hello" do
    ?. @ & ', world!'; # HIT
  else
    ?. @ & ' not found!';
end case;

########################################
# 1. Value in "when" may be anything ([...] or /.../)
# 2. "@" is a built-in variable in "case"
#        @ <- expression in "case ... is"
# 3. "&" means string concat
# 4. String quoted with ' or " or `
########################################
