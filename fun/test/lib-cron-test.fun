// cron: expression parsing, matching, intervals, lifecycle, run/stop. Booleans only.
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

fun whenText(n)
  if n = nil then result = 'nil'; return; end if;
  result = n['year'] & '-' & n['month'] & '-' & n['day'] & ' ' &
           n['hour'] & ':' & n['minute'] & ':' & n['second'];
end fun;

fun makeDue(s, id, n, nowMs)
  for j in s._jobs do
    if j['id'] = id then
      if j['kind'] = 'cron' then j['nextWall'] = n; end if;
      j['nextMs'] = nowMs;
      s._heapify();
      return;
    end if;
  end do;
end fun;

fun makeWait(s, id, n, nextMs)
  for j in s._jobs do
    if j['id'] = id then
      if j['kind'] = 'cron' then j['nextWall'] = n; end if;
      j['nextMs'] = nextMs;
      s._heapify();
      return;
    end if;
  end do;
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

// --- tick and next -------------------------------------------------------
var s = CronScheduler();
var fired = 0;
var sId = s.addJob('*/5 * * * *', () { fired += 1; });
var n5 = at(2026, 11, 12, 3, 5, 0);
makeDue(s, sId, n5, 0);
?. s._tick(n5, 0) = 1;
?. fired = 1;
?. s._tick(n5, 0) = 0;
?. fired = 1;

var seconds = CronScheduler();
fired = 0;
var secId = seconds.addJob('0-30 * * * * *', () { fired += 1; }, [withSeconds: true]);
var ns = at(2026, 11, 12, 3, 5, 10);
makeDue(seconds, secId, ns, 0);
?. seconds._tick(ns, 0) = 1;
?. fired = 1;
?. seconds._tick(ns, 0) = 0;

// --- independent instances -----------------------------------------------
var a = CronScheduler();
var b = CronScheduler();
var ah = 0;
var bh = 0;
var aId = a.addJob('*/5 * * * *', () { ah += 1; });
var bId = b.addJob('*/5 * * * *', () { bh += 1; });
makeDue(a, aId, n5, 0);
makeDue(b, bId, n5, 0);
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

// --- job identity and lifecycle -----------------------------------------
var life = CronScheduler();
var id1 = life.addJob('*/5 * * * *', () {});
var id2 = life.every('1s', () {});
?. id1 = 1;
?. id2 = 2;
?. (id1.type() = 3) or (id1.type() = 5);
?. (id2.type() = 3) or (id2.type() = 5);
?. life.removeJob(id1);
?. not life.removeJob(id1);
?. not life.removeJob(999);
?. not life.removeJob(nil);
?. not life.removeJob('2');
var id3 = life.addJob('*/5 * * * *', () {});
?. id3 = 3;

var other = CronScheduler();
?. other.addJob('*/5 * * * *', () {}) = 1;

// --- jobs() snapshot ----------------------------------------------------
var js = life.jobs();
?. js.@count() = 2;
?. js[0]['id'] = 2;
?. js[0]['kind'] = 'every';
?. js[0]['intervalMs'] = 1000;
?. (js[0]['intervalMs'].type() = 3) or (js[0]['intervalMs'].type() = 5);
?. js[1]['id'] = 3;
?. js[1]['kind'] = 'cron';
?. js[1]['expr'] = '*/5 * * * *';
?. js[1]['withSeconds'] = false;
?. js[1]['withSeconds'].type() = 11;
js[1]['id'] = 99;
?. life.jobs()[1]['id'] = 3;

var batch = CronScheduler();
batch.addJob('*/5 * * * *', () {});
batch.addJob('*/5 * * * *', () {});
for j in batch.jobs() do batch.removeJob(j['id']); end do;
?. batch.jobs().@count() = 0;

// --- removal and tick snapshot ------------------------------------------
var rem = CronScheduler();
var remHits = 0;
var rid = rem.addJob('*/5 * * * *', () { remHits += 1; });
rem.removeJob(rid);
?. rem._tick(n5, 0) = 0;
?. remHits = 0;

var del = CronScheduler();
var order = new [];
var delB = 0;
var delA = del.addJob('*/5 * * * *', () {
  order.@add('A');
  del.removeJob(delB);
});
delB = del.addJob('*/5 * * * *', () {
  order.@add('B');
});
makeDue(del, delA, n5, 0);
makeDue(del, delB, n5, 0);
?. del._tick(n5, 0) = 1;
?. order.@count() = 1;
?. order[0] = 'A';

var add = CronScheduler();
var addOrder = new [];
var addOnce = false;
var addCId = 0;
var addAId = add.addJob('*/5 * * * *', () {
  addOrder.@add('A');
  if not addOnce then
    addOnce = true;
    addCId = add.addJob('*/5 * * * *', () { addOrder.@add('C'); });
  end if;
});
makeDue(add, addAId, n5, 0);
?. add._tick(n5, 0) = 1;
?. addOrder.@count() = 1;
makeDue(add, addCId, n5, 0);
?. add._tick(n5, 0) = 1;
?. addOrder.@count() = 2;
?. addOrder[1] = 'C';

var all = CronScheduler();
var allOrder = new [];
var allA = all.addJob('*/5 * * * *', () {
  allOrder.@add('A');
  for j in all.jobs() do all.removeJob(j['id']); end do;
});
var allB = all.addJob('*/5 * * * *', () { allOrder.@add('B'); });
makeDue(all, allA, n5, 0);
makeDue(all, allB, n5, 0);
?. all._tick(n5, 0) = 1;
?. allOrder.@count() = 1;
?. all.jobs().@count() = 0;

var self = CronScheduler();
var selfHits = 0;
var sid = 0;
sid = self.addJob('*/5 * * * *', () {
  selfHits += 1;
  self.removeJob(sid);
});
makeDue(self, sid, n5, 0);
?. self._tick(n5, 0) = 1;
?. self._tick(n5, 0) = 0;
?. selfHits = 1;
?. self.jobs().@count() = 0;

var ever = CronScheduler();
var everHits = 0;
var eid = ever.every('1s', () { everHits += 1; });
?. ever.removeJob(eid);
?. ever.jobs().@count() = 0;
?. ever._tick(n5, _cronNowMs() + 2000) = 0;
?. everHits = 0;

var ord = CronScheduler();
var oa = ord.addJob('* * * * *', () {});
var ob = ord.addJob('* * * * *', () {});
var oc = ord.addJob('* * * * *', () {});
ord.removeJob(ob);
var oj = ord.jobs();
?. oj.@count() = 2;
?. oj[0]['id'] = oa;
?. oj[1]['id'] = oc;

// --- invalid add does not consume an id ---------------------------------
var bad = CronScheduler();
?. raises(((){ bad.addJob('bad', () {}); }));
?. bad.addJob('* * * * *', () {}) = 1;

var imp = CronScheduler();
?. raises(((){ imp.addJob('0 0 31 2 *', () {}); }));
?. imp.addJob('* * * * *', () {}) = 1;

// --- onError ------------------------------------------------------------
var ehCount = 0;
var ehJob = nil;
var ehErr = nil;
var eh = CronScheduler([onError: (job, err) {
  ehCount += 1;
  ehJob = job;
  ehErr = err;
}]);
var ehId = eh.addJob('*/5 * * * *', () { raise 'boom'; });
makeDue(eh, ehId, n5, 0);
?. eh._tick(n5, 0) = 1;
?. ehCount = 1;
?. ehJob['id'] = 1;
?. (ehJob['id'].type() = 3) or (ehJob['id'].type() = 5);
?. ehJob['kind'] = 'cron';
?. ehJob['expr'] = '*/5 * * * *';
?. ehJob['withSeconds'] = false;
?. ehJob['withSeconds'].type() = 11;
?. ehJob['fn'] = nil;
?. ehErr <> nil;
?. ehErr['message'].subpos('boom') >= 0;
ehJob['id'] = 99;
?. eh.jobs()[0]['id'] = 1;

var eh2Count = 0;
var eh2Kind = '';
var eh2 = CronScheduler([onError: (job, err) {
  eh2Count += 1;
  eh2Kind = job['kind'];
}]);
var eh2Id = eh2.every('1s', () { raise 'boom'; });
var eh2Now = _cronNowMs() + 1000000;
makeDue(eh2, eh2Id, n5, eh2Now);
?. eh2._tick(n5, eh2Now) = 1;
?. eh2Count = 1;
?. eh2Kind = 'every';

var silent = CronScheduler();
var silentHits = 0;
var silentA = silent.addJob('*/5 * * * *', () { raise 'boom'; });
var silentB = silent.addJob('*/5 * * * *', () { silentHits += 1; });
makeDue(silent, silentA, n5, 0);
makeDue(silent, silentB, n5, 0);
?. silent._tick(n5, 0) = 2;
?. silentHits = 1;

var badHandler = CronScheduler([onError: (job, err) { raise 'handler boom'; }]);
var afterHits = 0;
var badA = badHandler.addJob('*/5 * * * *', () { raise 'job boom'; });
var badB = badHandler.addJob('*/5 * * * *', () { afterHits += 1; });
makeDue(badHandler, badA, n5, 0);
makeDue(badHandler, badB, n5, 0);
?. badHandler._tick(n5, 0) = 2;
?. afterHits = 1;

// --- engine wait and missed runs ----------------------------------------
var w = CronScheduler();
var wId = w.addJob('0 3 * * *', () {});
makeWait(w, wId, at(2026, 11, 12, 3, 0, 0), 1000);
?. w._nextWait(0) = 1000;

var we = CronScheduler();
var weId = we.every('1s', () {});
makeWait(we, weId, n5, 1000);
?. we._nextWait(900) = 100;

var hp = CronScheduler();
var h1 = hp.addJob('* * * * *', () {});
var h2 = hp.addJob('* * * * *', () {});
var h3 = hp.addJob('* * * * *', () {});
makeWait(hp, h1, at(2026, 11, 12, 0, 0, 0), 3000);
makeWait(hp, h2, at(2026, 11, 12, 0, 0, 0), 1000);
makeWait(hp, h3, at(2026, 11, 12, 0, 0, 0), 2000);
?. hp._heapPeek()['id'] = h2;
?. hp._heapPop()['id'] = h2;
?. hp._heapPeek()['id'] = h3;
?. hp._heapPop()['id'] = h3;
?. hp._heapPeek()['id'] = h1;

var lazy = CronScheduler();
var l1 = lazy.addJob('* * * * *', () {});
var l2 = lazy.addJob('* * * * *', () {});
makeWait(lazy, l1, at(2026, 11, 12, 0, 0, 0), 1000);
makeWait(lazy, l2, at(2026, 11, 12, 0, 0, 0), 2000);
lazy.removeJob(l1);
?. lazy._nextWait(0) = 1000;
?. lazy.jobs().@count() = 1;

var rb = CronScheduler();
var rbId = rb.addJob('0 3 * * *', () {});
makeWait(rb, rbId, at(2026, 11, 12, 3, 0, 0), 999999);
rb._rebaseCron(at(2026, 11, 12, 2, 0, 0), 1000);
?. rb._heapPeek()['nextMs'] = 1000 + 3600 * 1000;

var miss = CronScheduler();
var missHits = 0;
var missId = miss.addJob('* * * * *', () { missHits += 1; });
makeDue(miss, missId, at(2026, 11, 12, 0, 0, 0), 0);
?. miss._tick(at(2026, 11, 12, 10, 0, 0), 0) = 1;
?. missHits = 1;
?. miss._tick(at(2026, 11, 12, 10, 0, 0), 0) = 0;
?. missHits = 1;

// --- index regressions ---------------------------------------------------
var alias = CronScheduler();
var al1 = alias.addJob('* * * * *', () {});
var al2 = alias.addJob('* * * * *', () {});
?. not alias.removeJob(-1);
?. not alias.removeJob(1.5);
?. not alias.removeJob(4294967297);
?. not alias.removeJob(0);
?. alias.nextRun(-1) = nil;
?. alias.nextRun(1.5) = nil;
?. alias.nextRun(4294967297) = nil;
?. alias.jobs().@count() = 2;
?. alias.removeJob(al2);
?. alias.jobs().@count() = 1;
?. alias.removeJob(al1);
?. alias.jobs().@count() = 0;

var bulk = CronScheduler();
for i = 1 to 300 do bulk.addJob('* * * * *', () {}); end do;
for j in bulk.jobs() do bulk.removeJob(j['id']); end do;
?. bulk.jobs().@count() = 0;
?. bulk._heapN <= 256;

var nm = CronScheduler();
var nmId = nm.addJob('0 0 29 2 *', () {});
var nmJob = nm._byId['id:' & nmId];
var nmD = (nmJob['nextMs'] - _cronNowMs()) div 1000;
var nmW = _cronDiffSec(_cronNow(), nmJob['nextWall']);
?. nmD >= nmW - 2 and nmD <= nmW + 2;

var cb = CronScheduler();
var cbHits = 0;
var cbId = cb.addJob('* * * * *', () { cbHits += 1; });
makeWait(cb, cbId, at(2026, 11, 12, 10, 0, 0), 0);
?. cb._tick(at(2026, 11, 12, 9, 0, 0), 0) = 0;
?. cbHits = 0;
?. cb._tick(at(2026, 11, 12, 10, 0, 0), 3600 * 1000) = 1;
?. cbHits = 1;

var deep = CronScheduler();
var deepIds = new [];
for i = 1 to 16 do deepIds.@add(deep.addJob('* * * * *', () {})); end do;
for i = 0 to 15 do makeWait(deep, deepIds[i], at(2026, 11, 12, 0, 0, 0), (16 - i) * 1000); end do;
var deepOk = true;
var deepPrev = -1;
for i = 1 to 16 do
  var dj = deep._heapPop();
  if dj['nextMs'] < deepPrev then deepOk = false; end if;
  deepPrev = dj['nextMs'];
end do;
?. deepOk;

var lz = CronScheduler();
var lz1 = lz.addJob('* * * * *', () {});
var lz2 = lz.addJob('* * * * *', () {});
makeWait(lz, lz1, at(2026, 11, 12, 0, 0, 0), 100);
makeWait(lz, lz2, at(2026, 11, 12, 0, 0, 0), 500);
lz.removeJob(lz1);
?. lz._nextWait(0) = 500;

var nv = CronScheduler();
var nvId = nv.addJob('0 0 29 2 *', () {});
var nvNow = _cronNow();
var nvExp = 1.time() + _cronDiffSec(nvNow, _cronNext(nv._byId['id:' & nvId], nvNow)) / 86400;
var nvDiff = (nv.nextRun(nvId) * 1 - nvExp * 1) * 86400;
?. nvDiff > -3 and nvDiff < 3;

var nve = CronScheduler();
var nveId = nve.every('1h', () {});
makeWait(nve, nveId, n5, 0);
var nveSec = (nve.nextRun(nveId) * 1 - 1.time() * 1) * 86400;
?. nveSec > 0 and nveSec <= 3600;

var mb = CronScheduler();
var mbOrder = new [];
var mbA = mb.addJob('* * * * *', () { mbOrder.@add('A'); mb.stop(); });
var mbB = mb.addJob('* * * * *', () { mbOrder.@add('B'); });
makeDue(mb, mbA, n5, 0);
makeDue(mb, mbB, n5, 0);
?. mb._tick(n5, 0) = 1;
?. mbOrder.@count() = 1;
mb._stopped = false;
?. mb._tick(n5, 0) = 1;
?. mbOrder.@count() = 2;
?. mbOrder[1] = 'B';

// --- next occurrence and nextRun ----------------------------------------
var every5n = _cronParseExpr('*/5 * * * *', false);
?. whenText(_cronNext(every5n, at(2026, 11, 12, 3, 5, 0))) = '2026-11-12 3:10:0';
?. whenText(_cronNext(every5n, at(2026, 11, 12, 3, 5, 1))) = '2026-11-12 3:10:0';

var secn = _cronParseExpr('0-30 * * * * *', true);
?. whenText(_cronNext(secn, at(2026, 11, 12, 3, 5, 10))) = '2026-11-12 3:5:11';
?. whenText(_cronNext(secn, at(2026, 11, 12, 3, 5, 30))) = '2026-11-12 3:6:0';

var hourn = _cronParseExpr('0 9 * * *', false);
?. whenText(_cronNext(hourn, at(2026, 11, 12, 10, 0, 0))) = '2026-11-13 9:0:0';

var carryn = _cronParseExpr('*/15 * * * *', false);
?. whenText(_cronNext(carryn, at(2026, 11, 12, 3, 59, 0))) = '2026-11-12 4:0:0';

var monthn = _cronParseExpr('0 0 1 * *', false);
?. whenText(_cronNext(monthn, at(2026, 11, 12, 0, 0, 0))) = '2026-12-1 0:0:0';

var yearn = _cronParseExpr('0 0 1 1 *', false);
?. whenText(_cronNext(yearn, at(2026, 11, 12, 0, 0, 0))) = '2027-1-1 0:0:0';

var leapn = _cronParseExpr('0 0 29 2 *', false);
?. whenText(_cronNext(leapn, at(2026, 11, 12, 0, 0, 0))) = '2028-2-29 0:0:0';
?. whenText(_cronNext(leapn, at(2096, 3, 1, 0, 0, 0))) = '2104-2-29 0:0:0';

var orn = _cronParseExpr('0 0 1 * 1', false);
?. whenText(_cronNext(orn, at(2026, 11, 3, 0, 0, 0))) = '2026-11-9 0:0:0';

var strictn = _cronParseExpr('0 0 * * *', false);
?. whenText(_cronNext(strictn, at(2026, 11, 12, 0, 0, 0))) = '2026-11-13 0:0:0';

var secondsn = _cronParseExpr('0 0 0 * * *', true);
?. whenText(_cronNext(secondsn, at(2026, 11, 12, 0, 0, 0))) = '2026-11-13 0:0:0';

var impossiblen = _cronParseExpr('0 0 31 2 *', false);
?. whenText(_cronNext(impossiblen, at(2026, 11, 12, 0, 0, 0))) = 'nil';

?. _cronDiffSec(at(2026, 11, 12, 0, 0, 0), at(2026, 11, 13, 0, 0, 0)) = 86400;
?. _cronDiffSec(at(2026, 11, 12, 23, 59, 59), at(2026, 11, 13, 0, 0, 0)) = 1;
?. _cronDiffSec(at(2028, 2, 28, 0, 0, 0), at(2028, 2, 29, 0, 0, 0)) = 86400;
?. _cronDiffSec(at(2026, 11, 12, 0, 0, 0), at(2026, 11, 12, 1, 2, 3)) = 3723;

var nr = CronScheduler();
var nrid = nr.addJob('0 0 1 1 *', () {});
?. nr.nextRun(nrid) <> nil;
?. nr.nextRun(nrid) * 1 > 1.time() * 1;
?. nr.nextRun(999) = nil;
?. nr.nextRun(nil) = nil;
var nre = CronScheduler();
var nreid = nre.every('1s', () {});
?. nre.nextRun(nreid) <> nil;
