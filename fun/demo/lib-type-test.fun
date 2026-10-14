
########################################
# test for lib-type.fun
########################################

use '..\lib\lib-type.fun';

test();

fun test()
  ?. 123.toStr() & 456.toStr(); # Auto conversion, same to 123 & 456
  ?. '123'.toNum() * 2;         # Auto conversion, same to '123' * 2

  ?. '2010-05-12 15:53:59'.toTime() + 100;
  ?. 'a'.toByte();
  ?. 0x41.toChar();

  if [] then                    # Auto convert to false
    ?. '[]';
  else
    ?. 'not []';                # HIT
  end if;

  if [1, 2, 3] then             # Auto convert to true
    ?. '[1, 2, 3]';             # HIT
  else
    ?. 'not [1, 2, 3]';
  end if;

  if 'true' or 'yes' or 'NOT_BLANK' then # true  <- true, yes, or other NOT BLANK string
    ?. 'true or yes or NOT_BLANK';
  elsif 'false' or 'no' or '' then       # false <- false, no, or BLANK
    ?. 'false or no or BLANK';
  end if;
end fun;
