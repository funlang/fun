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
del.addJob('*/5 * * * *', () {
  order.@add('A');
  del.removeJob(delB);
});
delB = del.addJob('*/5 * * * *', () {
  order.@add('B');
});
?. del._tick(n5, 0) = 1;
?. order.@count() = 1;
?. order[0] = 'A';

var add = CronScheduler();
var addOrder = new [];
var addOnce = false;
add.addJob('*/5 * * * *', () {
  addOrder.@add('A');
  if not addOnce then
    addOnce = true;
    add.addJob('*/5 * * * *', () { addOrder.@add('C'); });
  end if;
});
?. add._tick(n5, 0) = 1;
?. addOrder.@count() = 1;
?. add._tick(n5, 0) = 1;
?. addOrder.@count() = 2;
?. addOrder[1] = 'C';

var all = CronScheduler();
var allOrder = new [];
all.addJob('*/5 * * * *', () {
  allOrder.@add('A');
  for j in all.jobs() do all.removeJob(j['id']); end do;
});
all.addJob('*/5 * * * *', () { allOrder.@add('B'); });
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

// --- onError ------------------------------------------------------------
var ehCount = 0;
var ehJob = nil;
var ehErr = nil;
var eh = CronScheduler([onError: (job, err) {
  ehCount += 1;
  ehJob = job;
  ehErr = err;
}]);
eh.addJob('*/5 * * * *', () { raise 'boom'; });
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
eh2.every('1s', () { raise 'boom'; });
?. eh2._tick(n5, _cronNowMs() + 1000000) = 1;
?. eh2Count = 1;
?. eh2Kind = 'every';

var silent = CronScheduler();
var silentHits = 0;
silent.addJob('*/5 * * * *', () { raise 'boom'; });
silent.addJob('*/5 * * * *', () { silentHits += 1; });
?. silent._tick(n5, 0) = 2;
?. silentHits = 1;

var badHandler = CronScheduler([onError: (job, err) { raise 'handler boom'; }]);
var afterHits = 0;
badHandler.addJob('*/5 * * * *', () { raise 'job boom'; });
badHandler.addJob('*/5 * * * *', () { afterHits += 1; });
?. badHandler._tick(n5, 0) = 2;
?. afterHits = 1;
