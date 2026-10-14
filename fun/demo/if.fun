
########################################
# if
########################################
#   if    expression then cmds
# { elsif expression then cmds }    0..n
# [ else                  cmds ]    0..1
#   end if;
########################################

if true then
  ?. true; # HIT
end if;

if false then
  ?. false;
else
  ?. true; # HIT
end if;

if false then
  ?. false;
elsif true then
  ?. true; # HIT
else
  ?. "What's wrong with you?";
end if;

########################################
# 1. Comments start with "#" or "//"
#    Comment block: #* ... #
# 2. "true", "false" are keywords
# 3. "?." means output (append extra \r\n)
#    "?," means output (append a blank' ')
#    "?:" means output (append a TAB     )
#    "?"  means output (without any extra)
########################################
