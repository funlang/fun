
########################################
# functional-anonymous
########################################
#   fun ( parameters ) { cmds }
########################################
#   fun (            ) { cmds }
########################################
#       (            ) { cmds }
########################################
#                      { cmds }
########################################

fun If(a, b, c)
  if a then
    return b();
  elsif c <> null then
    return c();
  end if;
end fun;

fun Loop(a, b)
  while a() do
    b();
  end do;
end fun;

fun For(init, cond, nex1, code)
  init();
  while cond() do
    code();
    nex1();
  end do;
end fun;

fun testIf()
  If(
    true,
    {?.true}            # Anonymous function (Lambda calculus)
  );

  If(
    false,
    {?.false},          # Anonymous function (Lambda calculus)
    {?.true}            # Anonymous function (Lambda calculus)
  );
end fun;
testIf();

fun testLoop()
  var i = 0;
  var s = 0;

  Loop(
    {return i < 10},    # Anonymous function (Lambda calculus)
    {?, i; i += 1}      # Anonymous function (Lambda calculus)
  );
  ?. 'DONE';

  For(
    {i = 1; s = 0},     # Anonymous function (Lambda calculus)
    {@ = i <= 1000},    # Anonymous function (Lambda calculus)
    {i += 1},           # Anonymous function (Lambda calculus)
    {s += i}            # Anonymous function (Lambda calculus)
  );
  ?. s;
end fun;
testLoop();

########################################
# 1. "@" is a built-in variable in "fun"
#        @ <- result
# 2. {...} <- (){} <- fun(){}
#        with parameters must use
#          fun(parameters){} or
#             (parameters){}
# 3. "?." means output (append extra \r\n)
#    "?," means output (append a blank' ')
#    "?:" means output (append a TAB     )
#    "?"  means output (without any extra)
########################################
