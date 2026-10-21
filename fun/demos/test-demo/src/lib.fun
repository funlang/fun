fun add(a, b)
  result = a + b;
end fun;

fun safe_div(a, b)
  if b = 0 then
    raise 'division by zero';
  end if;
  result = a / b;
end fun;
