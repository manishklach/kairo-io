# Kernel Patch Notes

## Target File

The first experimental kernel patch targets:

- `block/mq-deadline.c`

It is written against the Linux 6.8.12 `mq-deadline` structure found locally in the workspace.

Local validation status:

- `kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch` was checked against a Linux 6.8.12 source tree
- the patch applies cleanly with `git apply --check`
- a focused build of `block/mq-deadline.o` completed after validating the Kairo sysfs attribute plumbing

## Classification Method

The patch uses request `ioprio` as a temporary local classification mechanism:

- `IOPRIO_CLASS_RT`, prio `0`, read => decode-critical read
- `IOPRIO_CLASS_RT`, prio `1`, read => reserved for prefetch
- `IOPRIO_CLASS_BE`, prio `7`, write => prefill write

Only decode-read priority is mandatory in the first patch.

## Dispatch Policy

When `kairo_enable` is true:

- scan the RT-priority request bucket for decode-critical reads
- dispatch decode reads before the normal priority-order walk
- stop forcing decode dispatch after a small decode budget is reached
- return to existing `mq-deadline` dispatch behavior afterward

When `kairo_enable` is false:

- preserve normal `mq-deadline` behavior

## Starvation Avoidance

The patch does not replace the scheduler’s existing write-starvation logic. It only inserts a decode-first fast path ahead of the usual dispatch walk and bounds that preference with a simple decode budget. That keeps background writes moving through the existing fallback logic.

## Stats

The first patch exports a small set of `mq-deadline` iosched controls and counters for local validation:

- `kairo_enable`
- `kairo_decode_budget`
- `kairo_decode_dispatches`
- `kairo_normal_dispatches`
- `kairo_starvation_escapes`

These are intended for local inspection through `/sys/block/<dev>/queue/iosched/` and for collection by `scripts/collect_block_stats.sh`.

Internally, the patch tracks:

- `kairo_decode_dispatches`
- `kairo_normal_dispatches`
- `kairo_starvation_escapes`

## Known Limitations

- classification depends on local `ioprio` conventions
- decode detection is only approximate for the POC
- prefetch and eviction are not fully handled in the first patch
- the patch is intended for local validation, not a permanent interface
