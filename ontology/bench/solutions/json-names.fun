fun names(text)
  result = new [];
  var doc = text.getJson(json: true);
  if doc.users <> nil then
    for u in doc.users do
      result.@add(u.name);
    end do;
  end if;
end fun;
