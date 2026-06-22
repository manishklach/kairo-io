# Kairo Kernel Deep Dive: Stage 1 and Stage 2

This note describes the compile-targeted Kairo foundation stack for Linux
6.8.x. It focuses on the experimental kernel path only and avoids later
RFC-only architecture stages.

## 1. Where request classification lives

Request classification is introduced in `include/linux/blk_types.h` and
`include/linux/blk-mq.h`.

- `enum kairo_io_class` defines the local RFC/POC request classes.
- `struct kairo_request_hints` attaches Kairo metadata to `struct request`.
- `kairo_init_request_hints()` clears that metadata when a request is
  initialized.
- `blk_mq_rq_ctx_init()` in `block/blk-mq.c` is the Linux 6.8.x request init
  hook used for that reset.

## 2. How ioprio fallback maps into Kairo classes

The foundation stack uses `ioprio` as the temporary userspace-to-kernel hint
path because it is already exercised by `bench/kairo_bench.c`.

Fallback mapping:

- RT prio 0 read -> `KAIRO_IO_DECODE_READ`
- RT prio 1 read -> `KAIRO_IO_PREFETCH_READ`
- BE prio 7 write -> `KAIRO_IO_PREFILL_WRITE`
- `REQ_OP_DISCARD` or `REQ_OP_WRITE_ZEROES` -> `KAIRO_IO_EVICT`
- anything else -> `KAIRO_IO_NORMAL`

Classification order is:

1. explicit `rq->kairo_hints.io_class`
2. `ioprio` fallback
3. request-op fallback
4. normal I/O

## 3. How mq-deadline dispatch is modified

The foundation stack adds a Kairo-specific selection layer ahead of the normal
`mq-deadline` priority walk.

- `dd_kairo_dispatch_decode_request()` scans the RT read FIFO for decode reads
- `dd_kairo_dispatch_prefetch_request()` scans the RT read FIFO for prefetch
  reads
- normal BE and IDLE dispatch still uses `__dd_dispatch_request()`
- aged-priority escape still uses `dd_dispatch_prio_aged_requests()`

The patch does not replace `mq-deadline` queue structures. It biases selection
while continuing to remove requests through `deadline_move_request()`.

## 4. How decode priority works

Decode reads are the highest-priority Kairo class.

- `kairo_enable` gates the experimental path
- `kairo_decode_budget` caps consecutive decode dispatches
- the decode helper scans only the RT read FIFO
- once it selects a request, it consumes that request through
  `deadline_move_request()` and mirrors the tail dispatch bookkeeping from
  `__dd_dispatch_request()`

That approach avoids ad hoc removal from scheduler data structures.

## 5. How prefetch deadlines work

Prefetch reads are weaker than decode reads but stronger than background writes
when they are close to their deadline.

- `kairo_prefetch_budget` allows limited prefetch progress even when a
  deadline is not yet near
- `kairo_prefetch_deadline_us` defines the urgency window
- `dd_kairo_prefetch_deadline_near()` compares the request hint deadline with
  `ktime_get_ns()`
- if no explicit deadline exists, prefetch stays on the budget-controlled path
  and does not count as a deadline hit
- prefetch dispatch is allowed only when no decode read is queued

This keeps prefetch from preempting decode while still giving it a bounded path
forward.

## 6. How prefill demotion works

Prefill writes remain dispatchable, but the foundation stack tracks when they
lose priority to decode or urgent prefetch work.

- `dd_kairo_should_observe_prefill_demotion()` determines whether queued
  prefill writes are being deferred by higher-priority work
- `kairo_prefill_dispatches` counts prefill writes that do get issued
- `kairo_prefill_demotion_observations` counts per-dispatch observed deferral
  opportunities

The policy is accounting-oriented. It does not block writes indefinitely.

## 7. How eviction and discard are deprioritized

Eviction traffic maps to `KAIRO_IO_EVICT`.

- discard and write-zeroes requests classify as evict traffic
- `dd_kairo_should_observe_evict_demotion()` tracks when evict work is
  deferred behind decode or urgent prefetch
- `kairo_evict_dispatches` and `kairo_evict_demotion_observations` expose both
  behaviors

This makes eviction the lowest-priority Kairo class in the foundation stack.

## 8. How starvation protection is preserved

The foundation stack preserves existing `mq-deadline` starvation behavior
instead of replacing it.

- `dd_dispatch_prio_aged_requests()` still runs before the normal dispatch walk
- non-RT writes can still escape when aged scheduling selects them
- `kairo_starvation_escapes` counts the cases where non-RT writes issue while
  RT work is queued

The goal is read bias, not permanent write suppression.

## 9. What sysfs counters prove

The foundation sysfs counters are meant to prove that the experimental path is
being exercised.

Tunables:

- `kairo_enable`
- `kairo_decode_budget`
- `kairo_prefetch_budget`
- `kairo_prefetch_deadline_us`

Counters:

- `kairo_decode_dispatches`
- `kairo_prefetch_dispatches`
- `kairo_prefetch_deadline_hits`
- `kairo_prefetch_budget_skips`
- `kairo_prefill_dispatches`
- `kairo_prefill_demotion_observations`
- `kairo_evict_dispatches`
- `kairo_evict_demotion_observations`
- `kairo_normal_dispatches`
- `kairo_starvation_escapes`

Together they show whether Kairo-classified requests were observed, dispatched,
or deferred.

## 10. What remains unsafe or unvalidated

The foundation stack is compile-targeted, not fully validated.

- boot validation is still pending
- runtime sysfs visibility is still pending until a patched kernel is booted
- counter increments under `kairo_bench` are still pending
- the hint source is still primarily `ioprio`, not a full `io_uring` metadata
  path
- deadline semantics for prefetch are local RFC/POC behavior and may need more
  tuning after real mixed-workload runs
