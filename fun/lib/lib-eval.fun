// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

//==============================================================
// eval
//  $name => eval() or set[name]
//  {...} => loop, not recursion
//  {.*.} => tree, recursive - *
//  { <h> {...*...} <f> } => all
//==============================================================
fun eval(str, set, args, ind)
  args = args or new [];
  result = str.replace(/\*|\$[@$\w]++|(?:\{(?P<h>[^{}]*+))?(?P<v>\{[^{}]++\})(?:(?P<f>[^{}]*+)\})?/g, (m){
    var v = m.value();
    case v.substr(0, 1) is
      when '*' do
        result = evals(str, set, args, ind);
      when '$' do
        result = set[v.substr(pos: 1)];
      when '{' do
        if m.@('h') & m.@('f') <> '' then
          args.head = m.@('h');
          args.foot = m.@('f');
          v         = m.@('v');
        end if;
        result = evals(v.substr(1, - 2), set, args, ind);
    end case;
  });
end fun;

fun evals(str, set, args, ind)
  result = '';
  if set.@nodes <> nil and set.@nodes.@count() > 0 then
    result = args.head;
    for n in set.@nodes do
      result &= ind & eval(str, n, args, args.ind & ind);
    end do;
    result &= args.foot;
  end if;
end fun;
