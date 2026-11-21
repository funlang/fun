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

?. 'worker tests: pass=' & pass & ' fail=' & failed;
if failed > 0 then
  raise 'worker tests failed';
end if;
