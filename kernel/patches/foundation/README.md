# Kairo Foundation Patch Stack

This directory contains the compile-targeted Kairo kernel core.

It is separate from the broader `kernel/patches/0001` through `0009`
RFC/POC architecture series, which preserves the larger research direction.

## Purpose

The foundation stack is the serious local apply and compile target for Linux
6.8.x. It focuses only on the kernel core needed for measurable Kairo storage
experiments:

- request classification
- `ioprio` fallback classification
- `mq-deadline` decode priority
- prefetch deadline handling
- prefill demotion accounting
- evict and discard accounting
- sysfs tunables and counters

## Scope Notes

- current signaling path is `ioprio` fallback
- no stable UAPI is introduced
- no LKML submission is intended at this stage
- patches should be applied in order

## Patch Order

1. `0001-kairo-request-classification.patch`
2. `0002-kairo-mq-deadline-decode-priority.patch`
3. `0003-kairo-prefetch-prefill-evict-policy.patch`
4. `0004-kairo-mq-deadline-sysfs-counters.patch`
5. `0005-kairo-foundation-tracepoints.patch` (optional; apply with `--with-tracepoints`)

## Target Kernel

The target kernel series for this stack is Linux `6.8.x`.

## Applying with Tracepoints

By default, only patches 0001-0004 are applied. To also include foundation
tracepoints (0005):

```bash
./kernel/integration/linux-6.8/apply_foundation_stack.sh /path/to/linux-6.8 --with-tracepoints
```

Patch 0005 adds four compile-targeted tracepoints:
- `kairo_request_classified`
- `kairo_decode_dispatch`
- `kairo_prefetch_dispatch`
- `kairo_write_demoted`

See `docs/stage11_foundation_tracepoints.md` for details.
