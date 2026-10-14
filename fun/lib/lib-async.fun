// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

use 'lib-os.fun';
use 'lib-base.fun';

var wParams = 0;
var asyncs  = new [];
class AsyncClass(hwnd, message)
  var env = new [];
  var envs = new [];
  var wParam = wParams; wParams += 1;
  asyncs[wParam] = this;
  var fxExec;
  var fxWait;
  var fxDone;

  fun exec(fx)
    this.fxExec = fx;
    result = this;
  end fun;

  fun await(fx)
    this.fxWait = fx;
    result = this;
  end fun;

  fun done(fx)
    this.fxDone = fx;
    result = this;
  end fun;

  fun go()
    result = true;
    var vars = new [];
    var lParam = this.envs.@count();
    this.envs[lParam] = vars;
    if this.fxExec <> nil then
      result = this.fxExec(this, vars);
    end if;

    if result then
      if this.fxWait <> nil then
        var fxAwait = (){ //?. 'fxAwait';
          try
            this.fxWait(this, vars); //?. 'fxWait done.'; ?, this.hwnd; ?, this.message; ?, this.wParam; ?. lParam;
          except
            vars.ret = '$@ @ $@@()'.eval();
            vars.code = -1;
          end try;
          var r = PostMessage(this.hwnd, this.message, this.wParam, lParam); //?, 'in await'; ?. r;
        };
        var s  = ' '.x(4);
        vars.thread = CreateThread(nil, 0, fxAwait.@toCallback(this, ':i', true, thread: true), '', 0, s);
      elsif this.fxDone <> nil then
        this.fxDone(this, vars);
      end if;
    end if;
  end fun;
end class;

class AsyncCmdClass = AsyncClass()
  fun cmd(cmdLine, timeout, dir, temp, args)
    result = this.exec((async, env){
      env.args = args;
      env.timeout = timeout;
      env.temp = ifa(temp=nil, ->GetTempPath(), ->temp);
      env.sh = 'Wscript.Shell'.newobj();
      env.sh.CurrentDirectory = ifa(dir=nil, ->env.temp, ->dir);
      if cmdLine =~ /^\s*+"*+\s*+cmd\.exe/i then
        env.cmdLine = cmdLine;
        env.ex = nil;
      else
        env.ex = env.sh.Exec(cmdLine);
      end if;
      result = true;
    }).await((async, env){ //?. 'fxWait';
      if env.ex = nil then
        var tmp = ifa(env.temp=nil, ->GetTempPath(1.time()*1), ->env.temp&1.time()*1);
        var cmd = env.cmdLine & '>' & tmp;
        env.sh.Run(cmd, 0, true);
        if env.args and env.args.tempPath <> nil then
          tmp = tmp.replace(env.temp, env.args.tempPath);
        end if;
        env.ret = tmp.load();
        tmp.move();
      else
        result = 0;
        try
          var tim = 1.time();
          var timeout = env.timeout / 1000 / 60 / 60 / 24;
          while env.ex.Status = 0 and 1.time() - tim < timeout loop
            sleep(6);
          end loop;
          if env.ex.Status = 0 then
            //env.ex.Terminate();
          end if;
          //if env.ex.Status = 1 then
          //  env.ret = env.ex.StdOut.ReadAll();
          //else
            env.ret = env.ex.StdOut.ReadAll() & env.ex.StdErr.ReadAll();
          //end if;
        except
          env.ret &= '[ERROR]$@ @ $@@()'.eval();
        end try;
        result = env.ex.Status;
      end if;
    });
  end fun;
end class;

class AsyncCmdClass2 = AsyncClass()
  fun cmd(cmdLine, timeout, dir, temp)
    result = this.exec((async, env){
      env.timeout = timeout;
      env.temp = ifa(temp=nil, ->GetTempPath(), ->temp);
      env.sh = 'Wscript.Shell'.newobj();
      env.sh.CurrentDirectory = ifa(dir=nil, ->env.temp, ->dir);
      env.ex = env.sh.Exec(cmdLine);
      result = true;
    }).await((async, env){ //?. 'fxWait';
      result = 0;
      var tim = 1.time();
      var timeout = env.timeout / 1000 / 60 / 60 / 24;
      while env.ex.Status = 0 and 1.time() - tim < timeout loop
        sleep(6);
      end loop;
      if env.ex.Status = 0 then
        //env.ex.Terminate();
      end if;
      if env.ex.Status = 1 then
        env.ret = env.ex.StdOut.ReadAll();
      else
        env.ret = env.ex.StdOut.ReadAll() & env.ex.StdErr.ReadAll();
      end if;
      result = env.ex.Status;
    });
  end fun;
end class;

fun onAsyncMsg(hwnd, message, wParam, lParam) //?, hwnd; ?, message; ?, wParam; ?. lParam;
  var a = asyncs[wParam];
  if a <> nil and a.envs[lParam] <> nil and a.fxDone <> nil then
    a.fxDone(a, a.envs[lParam]);
    a.envs[lParam].thread = 0;
  end if;
end fun;

fun stopThreads()
  for a in asyncs do
    for t in a.envs do
      if t.thread <> 0 then
        ?, 'Stop thread'; ?, t.thread; # *
        if t.sh <> nil and t.ex <> nil then
          t.ex.Terminate();
        end if; #
        ?, TerminateThread(t.thread, 0);
        Close(t.thread);
        ?. '[OK]';
      end if;
    end do;
  end do;
end fun;
