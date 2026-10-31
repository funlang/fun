// `compile(inline: true)` is lexical insertion: the returned module shares the
// caller's scope, so qualified access is a live view. Non-inline compile() is
// an isolated module and must not see caller locals.
fun outer()
  var x = 1;
  var m = 'fun g() result = x; end fun;'.compile(inline: true);
  ?. m.g();
  x = 2;
  ?. m.x;
  m.x = 3;
  ?. x;

  var f = 'fun h() result = x; end fun;'.compile();
  try
    ?. f.x;
  except
    ?. 'isolated';
  end try;
end fun;

outer();
