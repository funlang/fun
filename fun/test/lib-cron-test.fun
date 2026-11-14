// cron: expression parsing, matching, intervals, run/stop. Booleans only.
use 'fun/lib/cron.fun';

fun raises(fn)
  var bad = false;
  try
    fn();
  except
    bad = true;
  end try;
  result = bad;
end fun;

fun at(y, m, d, h, mi, s)
  var n = new [];
  n['year'] = y;
  n['month'] = m;
  n['day'] = d;
  n['hour'] = h;
  n['minute'] = mi;
  n['second'] = s;
  n['dow'] = _cronDow(y, m, d);
  result = n;
end fun;

// --- fields, macros and matching -----------------------------------------
var every5 = _cronParseExpr('*/5 * * * *', false);
?. every5['minute'][0];
?. every5['minute'][5];
?. every5['minute'][6] = nil;
?. _cronMatch(every5, at(2026, 11, 12, 3, 5, 0));
?. not _cronMatch(every5, at(2026, 11, 12, 3, 6, 0));
?. not _cronMatch(every5, at(2026, 11, 12, 3, 5, 1));

var ranged = _cronParseExpr('0 9 * JAN-MAR MON-FRI', false);
?. ranged['month'][1];
?. ranged['month'][3];
?. ranged['month'][4] = nil;
?. ranged['dow'][1];
?. ranged['dow'][5];
?. ranged['dow'][6] = nil;
?. _cronParseExpr('0 9 * * SUN', false)['dow'][0];

var macro = _cronParseExpr('@daily', false);
?. macro['minute'][0];
?. macro['hour'][0];
?. macro['domWild'];
?. macro['dowWild'];
var macroSec = _cronParseExpr('@daily', true);
?. macroSec['withSeconds'];
?. _cronMatch(macroSec, at(2026, 11, 12, 0, 0, 0));
?. not _cronMatch(macroSec, at(2026, 11, 12, 0, 0, 1));

var withSec = _cronParseExpr('0-30 * * * * *', true);
?. _cronMatch(withSec, at(2026, 11, 12, 3, 5, 30));
?. not _cronMatch(withSec, at(2026, 11, 12, 3, 5, 31));

// 2026-11-02 is Monday: DOM=1 OR DOW=Monday.
var domOrDow = _cronParseExpr('0 0 1 * 1', false);
?. _cronMatch(domOrDow, at(2026, 11, 2, 0, 0, 0));
?. _cronMatch(domOrDow, at(2026, 11, 1, 0, 0, 0));
?. not _cronMatch(domOrDow, at(2026, 11, 3, 0, 0, 0));

// --- invalid input -------------------------------------------------------
?. raises(((){ _cronParseExpr('0 0 * * * *', false); }));
?. raises(((){ _cronParseExpr('0 0 * * *', true); }));
?. raises(((){ _cronParseExpr('0 0 ? * *', false); }));
?. raises(((){ _cronParseExpr('*/0 * * * *', false); }));
?. raises(((){ _cronParseExpr('@reboot', false); }));
?. raises(((){ _cronDurationMs('0s'); }));
?. raises(((){ _cronDurationMs('1x'); }));
?. raises(((){ _cronDurationMs('5'); }));
?. _cronDurationMs('1s') = 1000;
?. _cronDurationMs('500ms') = 500;
?. _cronDurationMs('1m30s') = 90000;
?. _cronDurationMs(250) = 250;

// --- tick and lastKey ----------------------------------------------------
var s = CronScheduler();
var fired = 0;
s.addJob('*/5 * * * *', () { fired += 1; });
var n5 = at(2026, 11, 12, 3, 5, 0);
?. s._tick(n5, 0) = 1;
?. fired = 1;
?. s._tick(n5, 0) = 0;
?. fired = 1;

var seconds = CronScheduler();
fired = 0;
seconds.addJob('0-30 * * * * *', () { fired += 1; }, [withSeconds: true]);
var ns = at(2026, 11, 12, 3, 5, 10);
?. seconds._tick(ns, 0) = 1;
?. fired = 1;
?. seconds._tick(ns, 0) = 0;

// --- independent instances -----------------------------------------------
var a = CronScheduler();
var b = CronScheduler();
var ah = 0;
var bh = 0;
a.addJob('*/5 * * * *', () { ah += 1; });
b.addJob('*/5 * * * *', () { bh += 1; });
?. a._tick(n5, 0) = 1;
?. ah = 1;
?. bh = 0;
?. b._tick(n5, 0) = 1;
?. bh = 1;
?. ah = 1;

// --- real run/stop for an interval --------------------------------------
var rt = CronScheduler();
var hits = 0;
rt.every(20, () {
  hits += 1;
  if hits >= 3 then rt.stop(); end if;
});
rt.run();
?. hits >= 3;
