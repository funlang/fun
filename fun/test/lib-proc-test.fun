// lib-proc smoke test: ProcList plus a self-process memory scan. `use` inside
// a branch only defines names in that block, so the body is a function and the
// backend instance is passed in.
use 'fun/lib/lib-host.fun';
use 'fun/lib/lib-path.fun';

var getpid = LibC().getapi('getpid', ':i');
var exename = PathBase(0.arg());
var dot = exename.subpos('.');
if dot > 0 then exename = exename.substr(0, dot); end if;
var nameRe = ('^' & exename & '$').toRegex();

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
  var me = proc.ProcList(false, [exename], nil);
  ?. me.@count() > 0;
  var mef = proc.ProcList(true, [exename], nil);
  ?. mef.@count() > 0;
  ?. (mef[0].exe =~ (exename & '$').toRegex()) <> nil;
  ?. mef[0].exe.length() >= exename.length();

  // regex filter (exeLike)
  ?. proc.ProcList(false, nil, nameRe).@count() > 0;

  // memory scan of our own address space
  var m = proc.SearchMem(pid, /lib-proc/, 0, false);
  ?. m <> nil;
  ?. m.@@();
  var all = proc.SearchMem(pid, exename.toRegex(), 0, true);
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
