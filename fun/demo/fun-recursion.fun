
########################################
# fun-recursion
########################################

for i = 1 to 17 do
  ?. fact(i);

  fun fact(n)
    if n > 1 then
      result = n * fact(n - 1); # call fact recursion
    else
      result = 1;
    end if;
  end fun;
end do;
