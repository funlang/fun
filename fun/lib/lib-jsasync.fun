// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-async.fun';
use 'lib-ajax.fun';
use 'lib-ui.fun';

class AsyncAjax = AsyncClass()
  fun make(args, id)
    result = this.exec((async, env){
      env.args = args;
      env.id   = id;
      result = true;
    }).await((async, env){
      try
        CoInitialize(0);
        env.ajx = Ajax();
        result = env.ajx.go(args: env.args);
        env.ret = result;
        env.code = env.ajx.code;
        env.message = env.ajx.message;
      except
        ?. @;
        env.ret = @;
      end try;
    });
  end fun;
end class;

fun ajax_batch(reqs, aajx)
  var rets = new [];
  var ii = reqs.@count();
  for k: req in reqs do
    aajx.make(req).done((async, env){
      rets[env.id] = new [ret: env.ret, code: env.code, message: env.message];
      ii -= 1;
    }).go();
  end do;

  while ii > 0 do
    delay(100, true);
  end do;

  result = rets;
end fun;
