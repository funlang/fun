# Worker and shared-data model

Status: implemented in the opt-in `funcmd-mt` build (`FUN_THREADS=1`).
Release archives ship it as `fun/fun-mt` on linux-x64, linux-arm64,
macos-x64, macos-arm64 and win-x64; the nightly prerelease stages for
linux-loongarch64 and linux-riscv64 also carry it. From source, use
`src/prj/fun/make-linux-x86_64-mt.sh` (on any Linux host),
`FUN_THREADS=1 src/prj/fun/make-macos.sh`,
`FUN_THREADS=1 src/prj/fun/make-darwin.sh` (cross build), or
`src/prj/fun/make-win64-mt.bat` (`set FUN_THREADS=1` before
`make-win64.bat` also works). For the prerelease Linux targets, pass
`FUN_THREADS=1 FULL=1` to `make-linux-loongarch64.sh` or
`make-linux-riscv64.sh`. The default `funcmd` stays single-threaded and
reports a clear error on first use of `lib-worker`.

## Why a separate binary

Fun's per-node evaluation state (the expression value slot, function frame
stack, identifier binding, and similar fields) lives on the AST node. Two
threads evaluating the same AST therefore overwrite each other. A global
evaluation lock would make threads safe but serial, and making every node field
thread-local would cost every ordinary script.

The worker model avoids the problem instead of locking it:

- A worker parses its own module, so it owns a private AST.
- A worker gets a cloned `CEnv`, and `_ENV` is a thread variable.
- Nothing Fun-visible crosses a thread boundary by reference. Payloads and
  results are plain strings, and structured data travels as Fun Data (FD).
- On Unix (Linux and macOS), `cthreads` supplies the thread-safe FPC heap. It
  costs roughly 12-15% on single-threaded scripts, which is why it is a
  separate binary. Windows uses the native thread driver and system heap, so
  its MT build needs only `-dFunThreads`, not `-dUseCThreads`.

This means the same source function can run in many workers at once. The old
"same function cannot be re-entered" limitation still applies to one shared AST
or one shared `CFun` object, not to the same source file parsed independently.

## Crossing data

```fun
use 'lib-worker.fun';

var w = WorkerFile('job.fun', 'sum', (new [1000]).@toJson(fd: true));
var text = w.join(-1);          // raw string result, or nil on timeout
var err = w.error();            // worker-side message + traceback, or nil
if err <> nil then raise err; end if;
var value = text.getJson(fd: true);
```

- `WorkerFile(file, entry, payload)` parses `file` in the worker.
- `WorkerSource(source, entry, payload)` parses an in-memory module.
- `payload` is one string. Use `@toJson(fd: true)` for lists and maps.
- The entry function takes one payload argument and may return a string or a
  number. Return FD when the caller needs structure.
- A worker error is captured in the handle. It is never thrown across the
  thread boundary by the runtime.
- `join(timeout)` is milliseconds, `-1` waits forever, and `nil` means timeout.
  `alive()` and `id()` are also available.

`workerRun`, `workerMap`, `workerMapLimit`, and `workerAll` are convenience
wrappers. `workerMapLimit` is the right default for a large input: it keeps at
most `limit` workers alive and preserves input order.

## Shared named state

`Shared(name)` opens a process-wide string key/value store. Every thread that
opens the same name gets the same store, so the name can travel through a
payload instead of a handle.

```fun
var n = Shared('jobs');
n.set('done', 0);               // single-key set
n.add('done', 1);               // atomic read-modify-write
var d = n.get('done');          // copied string, or ''
if n.has('done') then ... end if;
n.del('done');                  // true if the key existed
n.clear();                      // remove every key
for i = 0 to n.count() - 1 do
  var key = n.keyAt(i);         // empty string when out of range
end do;
```

Guarantees:

- `set`, `get`, `has`, `del`, `clear`, `count`, `keyAt`, and `add` are
  individually atomic.
- Values are copied on the way in and out. A worker can never hold a Fun string
  that the main thread also owns.
- `add` converts the current value with `StrToInt64Def(value, 0)`, so a missing
  or non-numeric key starts from 0.

Limits:

- Values are strings. Encode structured values with FD.
- There is no multi-key transaction and no compare-and-swap. If two keys must
  change together, put both in one FD value or use a channel.
- `keyAt(i)` is protected per call, but an index is not a snapshot. The list can
  change between `count()` and `keyAt(i)`.
- A store is process-wide, not machine-wide or cross-process.

## Channels

`Channel(name)` opens a process-wide FIFO. Every thread that opens the same name
shares the queue.

```fun
var q = Channel('work');
q.send((new [id, value]).@toJson(fd: true));

var item = q.recv(1000);        // nil on timeout, -1 waits forever
var now  = q.tryRecv();         // nil if empty
q.close();                      // queued values still drain
```

Guarantees:

- `send` copies the payload into the queue.
- `recv(timeout)` drains queued values in FIFO order, then blocks in roughly
  1 ms steps. It returns `nil` on timeout or after the channel is closed and
  empty.
- `tryRecv` never blocks.
- `send` after `close` raises. `close` is sticky.
- `closed()` and `count()` inspect the queue under the channel lock.

Limits:

- The queue is unbounded. A fast producer can grow memory until the receiver
  catches up.
- There is no `select`, no priority, and no built-in backpressure. Add a second
  channel for acknowledgements, or bound the producer by the number of items it
  has in flight.
- `recv` blocks the calling thread. In an event loop, prefer `tryRecv` plus
  `workerTick`, or give the channel to a worker and keep the main thread free.
- A channel is process-wide, not cross-process.

## Completion on the main thread

Fun objects are not safe to touch from an arbitrary worker thread. Worker
callbacks therefore run on the thread that calls `workerTick`.

```fun
var results = new [];

var w = WorkerFile('job.fun', 'sum', '[1000]');
w.onDone(fun (text, err) {
  if err <> nil then
    results.@add('error: ' & err);
  else
    results.@add(text);
  end if;
});

// In the main event loop, for example once per poll iteration:
workerTick();
```

For an event loop with an `onTick` hook, `workerAttach` connects the two. The
`Scheduler` in `lib-winsock-base` has such a hook, so HTTP-style loops can drive
completions without calling `workerTick` themselves:

```fun
var s = Scheduler();
workerAttach(s);       // every s.Tick() now ends with workerTick()
```

- `Worker.onDone(fx)` can be set once per worker. It registers the worker in the
  module-level pending list.
- `workerTick()` fires callbacks for finished workers, returns the number fired,
  and re-raises the first callback error after running the rest.
- `workerPending()` reports the number of registered workers that have not been
  dispatched.
- `workerWaitAll(timeout)` joins every registered worker and then dispatches.
  It is convenient for scripts, but it blocks the main thread.
- `workerAttach(scheduler)` assigns `scheduler.onTick = fun () { workerTick(); }`,
  so a loop that already has an `onTick` hook needs one wiring call. It returns
  the scheduler. Callback errors propagate out of the tick.
- `workerTick` is a plain function, so any event loop can call it. It does not
  depend on a particular HTTP or socket loop.

## Cancelling a job

`w.cancel()` and `task.cancel()` ask a running job to stop at its next safe
point. A safe point is a loop iteration (`for`, `while`, `loop`, `for..in`), a
Fun function or method call, or a blocking `Channel.recv`. The worker then
finishes with the error `worker cancelled`; the result is empty.

```fun
var w = WorkerFile('job.fun', 'spin', '[]');
if w.alive() then w.cancel(); end if;
var r = w.join(5000);          // empty string
var e = w.error();             // "worker cancelled\n" (plus traceback)
```

Cancellation is cooperative. A job blocked inside a native call, sleeping, or
inside a tight C loop that never calls back into Fun cannot be interrupted. The
flag is checked, not forced.

Scripts cannot catch it. `ECancelled` bypasses `try/except` (but `finally`
blocks still run), so job code cannot turn a cancel into a normal result.

## Resident pools

`WorkerFile` parses the module for every job. A pool keeps `size` resident
slots instead: each slot parses the module once and then handles jobs serially.

```fun
var p = WorkerPool('job.fun', 4);      // file, slot count
var t = p.submit('sum', payload);      // entry name, payload string
var r = t.join(-1);                    // raw result, nil on timeout
if t.error() <> nil then raise t.error(); end if;
p.close();
```

- `submit(entry, payload)` waits (in 1 ms steps) until a slot is free, so the
  pool size is also the concurrency limit. It returns a task handle with the
  same `join`/`result`/`error`/`alive`/`cancel` methods as a worker.
- One pool serves one module, but each job names its own entry function.
- Module globals persist between successful jobs on the same slot. They are
  private to that slot, so do not assume a single shared counter. Use `Shared`
  or `Channel` for cross-slot state.
- A job that raises (or is cancelled) is isolated: the slot rebuilds its
  environment by re-running the module before taking the next job.
- `idle()` reports free slots. A slot becomes idle before its task reports
  completion, so observing a finished task never leaves a stale busy slot.
- `close()` stops intake and waits for running jobs, then joins every slot
  thread. A job that was queued but never started finishes with
  `worker pool closed`.
- `poolMap(pool, entry, items, timeout)` and `poolRun(pool, entry, args,
  timeout)` are the convenience wrappers; `poolMap` uses the same `[item]` FD
  wrapping as `workerMap`.

## Idioms

1. Read-only fan-out: build a list, call `workerMapLimit`, consume results in
   order. Do not pass a mutable Fun list into a worker and expect it to change.
2. Producer/consumer: pass channel names through the payload, let workers send
   FD items, and let the main thread `tryRecv` or a consumer worker `recv`.
3. Shared counters and flags: `Shared.add` for counters, `Shared.set/get` for
   small state. Keep each key independently meaningful.
4. Errors: check `w.error()` before using a worker result. For callbacks, check
   the `err` argument. A worker failure does not abort other workers.
5. Bounded concurrency: use `workerMapLimit(file, entry, items, limit, timeout)`
   instead of creating one worker per item for a large list.
6. Output: the runtime locks `WriteOut` and `WriteErr` in MT builds, so `?.` and
   logging from several workers do not interleave bytes. Do not assume a line
   from one worker stays next to another line.

## Current limits

- Cancellation is cooperative: only loops, Fun calls and `Channel.recv` are
  safe points. Native blocking calls and foreign code are not interruptible.
- A pool is per module and per process. There is no dynamic resize, no
  priority, and no work stealing between slots; `submit` simply waits for a
  free slot.
- Pool slots keep module globals between jobs, while `WorkerFile` rebuilds them
  per job. Pick the model that matches the job's state expectations.
- No worker-to-worker direct message object. Use `Shared` or `Channel` names.
- No cross-process workers, no remote workers, and no distributed queues.
- MT builds cover Linux x64/arm64/loongarch64/riscv64, macOS x64/arm64 and
  Windows x64. There is no 32-bit or Delphi/WinCE `fun-mt`.
- No fairness or priority control. OS scheduling decides which worker runs.
- FFI callbacks into Fun from a thread that Fun did not create need a build with
  the thread-safe RTL and careful callback design. This model does not make
  arbitrary native callbacks safe.
- Module globals in a worker are private to that worker and are rebuilt for each
  job. Two jobs never share worker globals, even in the same source file.
