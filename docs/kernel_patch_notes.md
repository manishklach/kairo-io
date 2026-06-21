# Kernel Patch Notes

## Target File

The first experimental kernel patch targets:

- `block/mq-deadline.c`

It is written against the Linux 6.8.12 `mq-deadline` structure found locally in the workspace.

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

The first patch keeps minimal internal counters only:

- `kairo_decode_dispatches`
- `kairo_normal_dispatches`
- `kairo_write_starvation_escapes`

These counters are documented for local inspection and future export, but the first patch does not require a full sysfs or debugfs plumbing pass.

## Known Limitations

- classification depends on local `ioprio` conventions
- decode detection is only approximate for the POC
- prefetch and eviction are not fully handled in the first patch
- counters are internal only
- the patch is intended for local validation, not a permanent interface
