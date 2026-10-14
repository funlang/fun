// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

########################################
# lib-time
########################################
#   built-in (2)
########################################
#     a.time  () # 0.time(), a.time()
#     a.format() # yyyy-mm-dd hh:nn:ss:zzz
########################################

var date() = 1.time(); # return date & time
var time() = 0.time(); # return time
var qpf    = 1000/-1.time(); # -1: qpf, -2: qpc
var ms     = 24 * 60 * 60 * 1000;

class tick(qpc)
  qpc = qpc or 0;
  var t    = qpc.time();
  var get  = {
    if qpc < 0 then
      result = (qpc.time() - t) * qpf;
    else
      result = (qpc.time() - t) * ms div 1;
    end if;
    t      = qpc.time();
  };
  var getStr = {
    result = get();
    if result    < 100                   then
      result = result div 1              & ' milliseconds';
    elsif result < 1000 * 60             then
      result = result div 100       / 10 & ' seconds';
    elsif result < 1000 * 60 * 60        then
      result = result /  1000 div 6 / 10 & ' minutes';
    else
      result = result / 60000 div 6 / 10 & ' hours';
    end if;
  };
  var show = (s, ms){
    if ms = 0 then ms = 1; end if;
    result = s & ': ' & get() / ms;
  };
end class;

fun diffDate(y, m, d, default, diff, now)
  now = now or 1.time();
  result = default;
  try
    var mm = 'mm';
    var dd = 'dd';
    if diff in ['m', 'y'] then
      dd = 15;
      d  = 15;
    end if;
    if diff = 'y' then
      mm = 7;
      m  = 7;
    end if;
    result = now.format('yyyy-$mm-$dd'.eval()).toTime() - '$y-$m-$d'.eval().replace(/[^\d\-]++/g, '').toTime();
    if diff = 'm' then
      result = result / 30.436875 div 1;
    elsif diff = 'y' then
      result = result / 365.2425 div 1;
    end if;
  except
  end try;
end fun;
