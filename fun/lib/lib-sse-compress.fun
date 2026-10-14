// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-stream.fun';
use 'lib-regex.fun';
use 'lib-math.fun';

var Empty = ' ';
var ln = '\n'.escape();
fun SseCompress(Lines, str, all)
  Lines = Split(/\r?\n/, Lines);
  str = str or Stream();
  var o = '';
  for s in Lines do next when s = nil;
    var l = min(o.length(), s.length());
    var i = 0;
    loop
      exit when i >= l or o[i] <> s[i];
      i += 1;
    end loop;
    o = s;
    if i > 2 or all then
      str.Write(i & ')');
    else
      str.Write(Empty.x(i));
    end if;
    str.Write(s.substr(i) & ln);
  end do;
  result = str.Get();
end fun;

fun SseDecompress(Lines, str)
  Lines = Split(/\r?\n/, Lines);
  str = str or Stream();
  var o = '';
  for s in Lines do next when s = nil;
    var l = s.length();
    var i = 0;
    loop
      exit when i >= l or s[i] <> Empty;
      i += 1;
    end loop;
    if i = 0 then
      s = s.replace(/^(\d++)\)/, (m){
        result = '';
        i = m.@(1) * 1;
      });
    else
      s = s.substr(i);
    end if;
    o = o.substr(len: i) & s;
    str.Write(o & ln);
  end do;
  result = str.Get();
end fun;
