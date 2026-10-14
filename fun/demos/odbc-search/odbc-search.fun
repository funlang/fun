// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-proc.fun';
use 'lib-cmdline.fun';

var args  = CmdLineParams.args;
var pid   = args[1];
var mb    = args[2];

if pid = nil then
  ?. 'Usage: odbc-search.exe <pid> [size(MB), default 64MB]';
elsif pid = '*' and mb !~ %^/[^\s/]++/\w*+$% then
  ?. 'Usage: odbc-search.exe * /regex/options';
else
  var odbc = /(?:Provider|Driver)=("(?!%s|\{\d++\})[^"]++"|(?!%s|\{\d++\})[^;\x00-\x1f\x7f-\xff]++)(;([\w\s:])++=(?1))*?(;(?3)*?(Password|Pwd)=(?1))(?2)*|(?2)*?;\s*+Dsn=(?1)(?2)*/i;
  if pid = '*' then
    var ps = proc.ProcList(true);
    mb = mb.match(%^/([^\s/]++)/(\w*+)$%);
    var re = mb.@(1).toRegex(mb.@(2));
    for p in ps do
      next when not re.match(p.exe);
      var ms = proc.SearchMem(p.pid, odbc, all: true);
      ?, p.exe;
      if ms then
        ?. ms.@toJson(1);
      end if;
    end do;
    ?. 'end.';
  else
    try
      mb *= 1;
    except
      mb = 0;
    end try;

    var ms = proc.SearchMem(pid, odbc, mb);
    if ms then
      ?. '1 item found:';
      ?. ms.@@();
      ?. 'end.';
    end if;
  end if;
end if;
