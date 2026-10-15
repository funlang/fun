// lib-proc smoke test: ProcList plus a self-process memory scan. `use` inside
// a branch only defines names in that block, so the body is a function and the
// backend instance is passed in.
use 'fun/lib/lib-host.fun';

var getpid = LibC().getapi('getpid', ':i');

fun RunTests(proc)
  var pid = getpid();

  // process listing
  var ps = proc.ProcList(true);
  ?. ps.@count() > 0;
  var has1 = false;
  for p in ps do
    if p.pid = 1 then has1 = true; end if;
  end do;
  ?. has1;

  // filter by short name, then full path (the filter runs on the short name)
  var me = proc.ProcList(false, ['funcmd'], nil);
  ?. me.@count() > 0;
  var mef = proc.ProcList(true, ['funcmd'], nil);
  ?. mef.@count() > 0;
  ?. (mef[0].exe =~ /funcmd$/) <> nil;
  ?. mef[0].exe.length() >= 6;

  // regex filter (exeLike)
  ?. proc.ProcList(false, nil, /^funcmd$/).@count() > 0;

  // memory scan of our own address space
  var m = proc.SearchMem(pid, /lib-proc/, 0, false);
  ?. m <> nil;
  ?. m.@@();
  var all = proc.SearchMem(pid, /funcmd/, 0, true);
  ?. all <> nil;
  ?. all.@count() > 0;
end fun;

if IsMac() then
  use 'fun/lib/lib-proc-darwin.fun';
  RunTests(proc);
else
  use 'fun/lib/lib-proc-lnx.fun';
  RunTests(proc);
end if;
