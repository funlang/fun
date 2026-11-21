// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// lib-worker tests. On a non-MT build this prints one stable SKIP line and
// exits 0, so it can live in the normal regression roster. Run it with
// fun/funcmd-mt to exercise the real paths.

use 'fun/lib/lib-worker.fun';

var pass = 0;
var failed = 0;

fun check(name, ok)
  if ok then
    pass += 1;
    ?. 'ok   ' & name;
  else
    failed += 1;
    ?. 'FAIL ' & name;
  end if;
end fun;

var h = 'host'.arg().getJson(fd: true);
if h.threads <> 1 then
  ?. 'SKIP worker: funcmd-mt not in use';
  exit;
end if;

var job = 'fun/test/worker-job.fun';

// 1. basic worker, raw string result
var w = WorkerFile(job, 'sum', (new [1000]).@toJson(fd: true));
var r = w.join(-1);
check('join result', r = '500500');
check('no error', w.error() = nil);
check('not alive', not w.alive());

// 2. echo payload, independent AST
var w2 = WorkerFile(job, 'echo', 'hello-worker');
check('echo', w2.join(-1) = 'hello-worker');

// 3. workerMap: one worker per item, results in order
var sums = workerMap(job, 'fdadd', [[1, 2], [3, 4], [5, 6]], -1);
check('map count', sums.@count() = 3);
check('map values', sums[0] = 3 and sums[1] = 7 and sums[2] = 11);

// 3b. bounded map: at most three workers run at once, results stay in order
var pairs = [[1, 10], [2, 20], [3, 30], [4, 40], [5, 50],
             [6, 60], [7, 70], [8, 80], [9, 90]];
var lm = workerMapLimit(job, 'fdadd', pairs, 3, -1);
check('mapLimit count', lm.@count() = 9);
check('mapLimit values', lm[0] = 11 and lm[4] = 55 and lm[8] = 99);

// 4. workerRun: FD args in, FD result out
var rr = workerRun(job, 'fdadd', [[10, 20]], -1);
check('run fd', rr[0] = 30);

// 5. error is captured in the worker, not thrown across threads
var we = WorkerFile(job, 'fail', '[]');
var re = we.join(-1);
var ee = we.error();
check('error text', ee <> nil and ee.subpos('worker boom') >= 0);
check('error result empty', re = '');

// 6. timeout returns nil, then a later join returns the value
var ws = WorkerFile(job, 'slow', '[]');
check('timeout', ws.join(0) = nil);
check('timeout still alive', ws.alive());
check('second join', ws.join(-1) <> nil);

// 7. several workers concurrently
var ws2 = new [];
for i = 1 to 4 do
  ws2.@add(WorkerFile(job, 'sum', (new [1000 * i]).@toJson(fd: true)));
end do;
var all = workerAll(ws2, -1);
check('all count', all.@count() = 4);
check('all values', all[0] = '500500' and all[1] = '2001000'
                  and all[2] = '4501500' and all[3] = '8002000');

// 8. named shared store: workers mutate the same counter without sharing a Fun
// object. The values are serialized, and each get/set copies the bytes.
var sh = Shared('worker-test-counter');
sh.set('n', 0);
check('shared has', sh.has('n'));
check('shared count', sh.count() = 1);
var vals = workerMap('fun/test/worker-shared-job.fun', 'bump',
                     ['worker-test-counter', 'worker-test-counter',
                      'worker-test-counter', 'worker-test-counter'], -1);
check('shared final', sh.get('n') = '4');
var vs = 0;
for i = 0 to vals.@count() - 1 do vs += vals[i]; end do;
check('shared sum', vs = 10);
sh.set('s', 'hello');
check('shared string', sh.get('s') = 'hello');
check('shared add', sh.add('n', 10) = 14);
check('shared keyAt', sh.keyAt(0) = 'n' and sh.keyAt(1) = 's');
check('shared del', sh.del('s') and not sh.has('s'));
check('shared keyAt after del', sh.keyAt(0) = 'n' and sh.keyAt(1) = '');
sh.clear();
check('shared clear', sh.count() = 0);

// 9. named channel: FIFO in one thread, then producer worker -> main thread,
// then main thread -> consumer worker.
var ch = Channel('worker-test-chan-a');
check('channel empty', ch.count() = 0);
ch.send('one');
ch.send('two');
check('channel count', ch.count() = 2);
check('channel fifo', ch.recv(0) = 'one' and ch.recv(0) = 'two');
check('channel empty recv', ch.recv(0) = nil);

var cp = Channel('worker-test-chan-b');
var pw = WorkerFile(job, 'sendN', ['worker-test-chan-b', 5].@toJson(fd: true));
var got = 0;
for i = 1 to 5 do
  var cv = cp.recv(5000);
  if cv <> nil then got += cv.toNum(); end if;
end do;
check('channel worker sum', got = 15);
check('channel producer', pw.join(-1) = '5');

var cq = Channel('worker-test-chan-c');
var cw = WorkerFile(job, 'recvN', ['worker-test-chan-c', 4].@toJson(fd: true));
for i = 1 to 4 do cq.send('' & i); end do;
check('channel consumer', cw.join(-1) = '10');

var cc = Channel('worker-test-chan-d');
cc.close();
check('channel closed', cc.closed());
check('channel closed recv', cc.recv(0) = nil);
check('channel closed try', cc.tryRecv() = nil);
try
  cc.send('x');
  check('channel closed send', false);
except
  check('channel closed send', true);
end try;

// 10. onDone runs on the main thread, not on the worker thread. workerTick is
// the event-loop form; workerWaitAll joins and then dispatches.
var seen = new [];
var cbw = WorkerFile(job, 'echo', 'cb');
cbw.onDone(fun (r, e) {
  seen.@add('ok:' & r & ':' & (e = nil));
});
check('pending 1', workerPending() = 1);
check('waitAll', workerWaitAll(10000));
check('onDone fired', seen.@count() = 1 and seen[0] = 'ok:cb:true');
check('pending empty', workerPending() = 0);

// 11. onDone reports worker errors without throwing across the thread boundary
var errSeen = nil;
var ew = WorkerFile(job, 'fail', '[]');
ew.onDone(fun (r, e) {
  errSeen = e;
});
check('onDone error wait', workerWaitAll(10000));
check('onDone error', errSeen <> nil and errSeen.subpos('worker boom') >= 0);

// 12. a raising onDone callback does not starve later callbacks
var secondRan = false;
var bw = WorkerFile(job, 'echo', 'bad');
bw.onDone(fun (r, e) {
  raise 'callback boom';
});
var gw = WorkerFile(job, 'echo', 'good');
gw.onDone(fun (r, e) {
  secondRan = true;
});
var cbErr = nil;
try
  workerWaitAll(10000);
except
  cbErr = @;
end try;
check('callback error surfaced', cbErr <> nil and cbErr.subpos('callback boom') >= 0);
check('callback after error ran', secondRan);
check('callback queue empty', workerPending() = 0);

// 13. workerAttach drives onDone from an event loop's onTick hook
var tickRan = 0;
var ticker = new [onTick: nil];
workerAttach(ticker);
var aw = WorkerFile(job, 'echo', 'attached');
aw.onDone(fun (r, e) {
  tickRan += 1;
});
var spins = 0;
while workerPending() > 0 and spins < 100000 do
  ticker.onTick();
  spins += 1;
end do;
check('workerAttach fired', tickRan = 1 and spins < 100000);

// 14. concurrent regex use: the shared PCRE cache must stay consistent across
// workers, including the second-use JIT upgrade.
var rws = new [];
for i = 1 to 4 do
  rws.@add(WorkerFile(job, 'regexHammer', '500'));
end do;
var rout = workerAll(rws, -1);
check('regex workers', rout.@count() = 4);
check('regex values', rout[0] = '4786' and rout[1] = '4786'
                    and rout[2] = '4786' and rout[3] = '4786');

?. 'worker tests: pass=' & pass & ' fail=' & failed;
if failed > 0 then
  raise 'worker tests failed';
end if;
