# Worker and shared-data model

Status: implemented in the opt-in `funcmd-mt` build (`FUN_THREADS=1`). The
default `funcmd` stays single-threaded and reports a clear error on first use of
`lib-worker`.

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
- `cthreads` supplies the thread-safe FPC heap. It costs roughly 12-15% on
  single-threaded scripts, which is why it is a separate binary.

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

- No cancellation. A running worker runs to completion or to its own error.
- No resident worker pool. Every job reparses its module, so very small jobs pay
  parse cost per job. `workerMapLimit` limits concurrency, not parsing.
- No worker-to-worker direct message object. Use `Shared` or `Channel` names.
- No cross-process workers, no remote workers, and no distributed queues.
- No Windows or macOS MT build script yet. The current `funcmd-mt` target is
  Linux x86_64.
- No fairness or priority control. OS scheduling decides which worker runs.
- FFI callbacks into Fun from a thread that Fun did not create need a build with
  the thread-safe RTL and careful callback design. This model does not make
  arbitrary native callbacks safe.
- Module globals in a worker are private to that worker and are rebuilt for each
  job. Two jobs never share worker globals, even in the same source file.
