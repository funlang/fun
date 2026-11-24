fun countWords(text)
  result = new [];
  var ws = text.match(/\S+/g);
  if ws <> nil then
    for w in ws do
      result[w] = (result[w] or 0) + 1;
    end do;
  end if;
end fun;
