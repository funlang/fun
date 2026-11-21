// Copyright (c) 2010-2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT

// lib-worker: shared-nothing workers.
//
// A worker parses its own copy of a Fun module and runs it on a new OS thread.
// It never shares an AST, a CEnv, or a Fun value with the caller. That is the
// invariant that makes concurrent evaluation safe: every CExp result cell and
// every CVarStack belongs to exactly one worker.
//
// The native half (src/lib/worker.pas) only starts/joins a thread and moves
// payload/result strings. Everything here, including FD encoding and the
// ergonomic API, is ordinary Fun code.
//
// Requires funcmd-mt (the -dFunThreads -dUseCThreads build). The default
// funcmd reports `threads` as absent from 'host'.arg() and this module refuses
// to load, so a script cannot accidentally depend on a non-threaded binary.
//
// Basic use:
//
//   use 'lib-worker.fun';
//   var w = WorkerFile('job.fun', 'main', args.@toJson(fd: true));
//   var out = w.join(5000);          // nil on timeout
//   var err = w.error();             // nil on success
//   var value = out.getJson(fd: true);
//
// job.fun:
//
//   fun main(payload)
//     var args = payload.getJson(fd: true);
//     result = (args[0] + args[1]).toJson(fd: true);
//   end fun;

use 'lib-host.fun';

var _hostFacts = 'host'.arg().getJson(fd: true);

// Workers waiting for a main-thread onDone callback. Only the main thread
// touches this list.
var _pending = new [];

fun _requireThreads()
  if _hostFacts.threads <> 1 then
    raise 'lib-worker requires funcmd-mt (build with FUN_THREADS=1)';
  end if;
  result = true;
end fun;

// A running worker. `join` returns the entry function's result as a string,
// or nil when the timeout expires. `error` returns the worker-side error text
// (message plus traceback) or nil. Always inspect `error` before using a nil
// result: nil means timeout, an error means the worker raised.
class Worker(file, entry, payload, isFile)
  var h = 'Worker'.start(file, entry, payload, isFile);
  var doneCb = nil;

  // Run fx(result, error) on the thread that later calls workerTick().
  // result is the raw entry result string; error is nil on success. The
  // callback never runs on the worker thread.
  fun onDone(fx)
    if this.doneCb <> nil then raise 'worker.onDone already set'; end if;
    this.doneCb = fx;
    _pending.@add(this);
    result = this;
  end fun;

  // timeout is milliseconds; pass -1 to wait forever.
  fun join(timeout)
    result = this.h.join(timeout);
  end fun;

  fun wait()
    result = this.h.join(-1);
  end fun;

  // Result of a finished worker, without waiting. Empty string if it has not
  // produced one yet. Prefer join().
  fun result()
    result = this.h.result();
  end fun;

  fun error()
    result = this.h.error();
  end fun;

  fun alive()
    result = this.h.alive();
  end fun;

  fun id()
    result = this.h.id();
  end fun;
end class;

// A named, process-wide key/value store for shared mutable data. Every thread
// that calls Shared('same-name') gets the same store, so workers do not need
// to receive a handle through a payload. Values are strings (use FD for
// structured data); get/set copy the bytes, so no Fun string is shared between
// threads. Methods: get(key), set(key, value), has(key), count(), add(key, n),
// del(key), clear(), keyAt(i). Iterate keys with `for i = 0 to s.count() - 1`
// and `s.keyAt(i)`.
//
//   var n = Shared('counter');
//   n.set('jobs', 0);
//   // in a worker:
//   //   Shared('counter').add('jobs', 1);
fun Shared(name)
  _requireThreads();
  result = 'Shared'.open(name);
end fun;

// A named FIFO channel shared by every thread that opens the same name.
// Values are strings (FD-encode structured data). send(v) never blocks;
// recv(timeout) blocks up to timeout ms, or forever with -1, and returns nil
// on timeout or after close. tryRecv() never blocks, closed() and count()
// inspect the queue. Channels are process-wide, so passing the name through
// a payload is enough.
fun Channel(name)
  _requireThreads();
  result = 'Channel'.open(name);
end fun;

fun _nowMs()
  var p = -2;
  var f = -1;
  result = p.time() div (f.time() div 1000);
end fun;

// Run pending onDone callbacks on the calling (main) thread. Call this from
// your event loop; returns the number of callbacks fired. Callbacks of
// workers that finished are removed before they run, so a raising callback
// does not leave a stuck entry behind.
fun workerTick()
  var old = _pending;
  _pending = new [];
  var ready = new [];
  for w in old do
    if w.alive() then _pending.@add(w); else ready.@add(w); end if;
  end do;
  for w in ready do
    var cb = w.doneCb;
    w.doneCb = nil;
    if cb <> nil then cb(w.result(), w.error()); end if;
  end do;
  result = ready.@count();
end fun;

fun workerPending()
  result = _pending.@count();
end fun;

// Join every worker registered with onDone, firing callbacks as they finish.
// timeout is milliseconds and -1 waits forever. Returns true when nothing
// remains pending. In an event-driven program prefer workerTick() instead:
// it never blocks the main thread.
fun workerWaitAll(timeout)
  var start = _nowMs();
  var waiting = new [];
  for w in _pending do waiting.@add(w); end do;
  for w in waiting do
    var left = -1;
    if timeout >= 0 then
      left = timeout - (_nowMs() - start);
      if left < 0 then left = 0; end if;
    end if;
    w.join(left);
  end do;
  workerTick();
  result = _pending.@count() = 0;
end fun;

// File-based worker. This is the common form: the module is parsed by the
// worker, and relative `use` paths resolve from the file's own directory.
fun WorkerFile(file, entry, payload)
  _requireThreads();
  result = Worker(file, entry, payload, true);
end fun;

// In-memory source worker. Handy for tests and generated jobs. Relative `use`
// paths resolve from the current working directory.
fun WorkerSource(source, entry, payload)
  _requireThreads();
  result = Worker(source, entry, payload, false);
end fun;

// One-shot helper: encode `args` as FD, run, decode the result. `timeout` is
// milliseconds and -1 waits forever. Raises on a worker error; returns nil on
// timeout.
fun workerRun(file, entry, args, timeout)
  _requireThreads();
  var w = WorkerFile(file, entry, args.@toJson(fd: true));
  var r = w.join(timeout);
  var e = w.error();
  if e <> nil then raise e; end if;
  if r = nil then return nil; end if;
  result = r.getJson(fd: true);
end fun;

// Run the same entry over a list of inputs, one worker per item, then collect
// the results in input order. This is the simple read-only-data pattern: the
// input list is copied into each worker through FD, so no mutable Fun object
// is shared. For large lists use a bounded loop instead of spawning all at
// once.
//
// The payload is always one FD list. For a single value, pass [value]; the
// worker entry reads payload.getJson(fd: true)[0] and should return an FD list
// such as (new [value]).@toJson(fd: true). workerMap then unwraps [0].
fun workerMap(file, entry, items, timeout)
  _requireThreads();
  var n = items.@count();
  var ws = new [];
  var out = new [];
  for i = 0 to n - 1 do
    ws[i] = WorkerFile(file, entry, (new [items[i]]).@toJson(fd: true));
  end do;
  for i = 0 to n - 1 do
    var r = ws[i].join(timeout);
    var e = ws[i].error();
    if e <> nil then raise e; end if;
    if r = nil then
      out[i] = nil;
    else
      out[i] = r.getJson(fd: true)[0];
    end if;
  end do;
  result = out;
end fun;

// Wait for a list of workers and return their raw result strings in order.
// Raises the first worker error encountered. Useful when the caller wants to
// start all workers itself (for different entry functions or payloads). Decode
// with getJson(fd: true) when the entry returns FD.
fun workerAll(workers, timeout)
  _requireThreads();
  var n = workers.@count();
  var out = new [];
  for i = 0 to n - 1 do
    var r = workers[i].join(timeout);
    var e = workers[i].error();
    if e <> nil then raise e; end if;
    if r = nil then
      out[i] = nil;
    else
      out[i] = r;
    end if;
  end do;
  result = out;
end fun;
