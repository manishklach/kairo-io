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

## Target Kernel

The target kernel series for this stack is Linux `6.8.x`.
