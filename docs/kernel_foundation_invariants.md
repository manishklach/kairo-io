# Kairo Foundation Invariants

This note documents the Linux 6.8.x `mq-deadline` invariants that the
compile-targeted Kairo foundation stack depends on.

## Structures Touched

The foundation stack only touches existing `mq-deadline` scheduler state:

- `struct deadline_data`
- `struct dd_per_prio`
- `per_prio->fifo_list[DD_READ]`
- `per_prio->fifo_list[DD_WRITE]`
- `per_prio->sort_list[DD_READ]`
- `per_prio->sort_list[DD_WRITE]`
- `per_prio->dispatch`
- `per_prio->latest_pos[]`
- `per_prio->stats.dispatched`

The foundation stack does not introduce a parallel request queue or bypass the
normal `mq-deadline` request containers.

## Lists Scanned

Kairo scans only existing FIFO lists while `dd->lock` is held:

- decode selection scans the RT read FIFO
- prefetch selection scans the RT read FIFO
- demotion-observation accounting scans BE and IDLE write FIFOs

Kairo does not walk the dispatch list to select requests, and it does not
manually remove requests from red-black trees.

## Request Movement

Kairo selects decode and prefetch requests conservatively:

- a candidate request is identified from `fifo_list[DD_READ]`
- `deadline_move_request()` performs the actual removal from the FIFO, sort
  tree, and scheduler bookkeeping path
- the Kairo helper only mirrors the tail dispatch bookkeeping already present
  in `__dd_dispatch_request()`

That means list removal stays on the native `mq-deadline` path instead of
introducing custom list deletion logic.

## Scheduler-State Safety

Kairo avoids corrupting scheduler state by keeping the dispatch bias narrow:

- it does not mutate `per_prio->dispatch` directly
- it does not delete requests from FIFO lists with ad hoc list operations
- it preserves `blk_req_zone_write_lock(rq)` and `RQF_STARTED`
- it updates `latest_pos` and `stats.dispatched` the same way
  `__dd_dispatch_request()` does

If Kairo does not select a decode or prefetch request, control returns to the
existing `mq-deadline` dispatch logic.

## Ordinary RT Behavior

Kairo decode reads get the first opportunity and Kairo prefetch reads get the
second opportunity, both from the RT read FIFO only.

After those checks:

- `dd_dispatch_prio_aged_requests()` still runs
- the normal priority walk still starts at `DD_RT_PRIO`
- non-Kairo RT requests remain eligible through unchanged `mq-deadline`
  priority order

This keeps Kairo from accidentally skipping unrelated RT traffic.

## Write Starvation Protection

The foundation stack preserves the existing `mq-deadline` starvation path:

- aged-priority escape logic remains in place
- write dispatch can still happen when `mq-deadline` selects it
- `kairo_starvation_escapes` is only accounting on top of the native behavior

Kairo adds read bias, not a replacement starvation policy.

## Decode Budget

`kairo_decode_budget` bounds consecutive decode dispatches on the Kairo path.

- if the budget is exhausted, Kairo decode selection stops
- once a non-Kairo dispatch happens, the decode budget is reset

This prevents decode preference from becoming an unbounded RT read drain.

## Prefetch Budget

`kairo_prefetch_budget` controls non-urgent prefetch progress.

- explicit deadlines can trigger urgent prefetch dispatch
- prefetch requests without an explicit deadline are budget-controlled only
- `kairo_prefetch_deadline_hits` counts only explicit near-deadline dispatches
- `kairo_prefetch_budget_skips` counts budget exhaustion for non-urgent
  prefetch candidates

This keeps prefetch separate from decode and avoids overstating deadline-driven
behavior when only `ioprio` hints exist.

## Remaining Gaps

The following are still unvalidated:

- boot validation of the patched kernel
- runtime sysfs visibility on a booted patched kernel
- counter movement under `kairo_bench`
- mixed-workload behavior beyond local apply/build validation
- whether the local `block/blk-mq.o` build failure is entirely external to the
  Kairo foundation path
