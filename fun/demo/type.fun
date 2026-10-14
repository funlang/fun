
########################################
# type
########################################
#   Number: [0-9]+(\.[0-9]+)?(e-?[0-9]+)?|0x[0-9a-f]+|0b[01]+
#   String: Quoted with ' or " or `
#   Time:   @String
#   Bool:   true/false
#   Null:   null/nil
########################################

# Number
?. 123456789;
var n = 1.23456789;             ?. n;
n = 0xffffffff;                 ?. n;

# String
?. "This is a string.";
var s = 'Hello, string.';       ?. s;
?. 'it''s me'; // '...''...', "...""...", `...``...`, `...`id`...` (for quine)

# Time
?. @"2010-04-09 15:35:15";
var t = @'2010-04-09 15:35:15'; ?. t;

# Bool
?. true;
var b = false;                  ?. b;

# Null
?. '[' & null & ']';
