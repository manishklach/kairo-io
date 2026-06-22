# Kairo Kernel Foundation Stack

Kairo keeps two kernel tracks in the repository.

## Broad RFC/POC Architecture

The top-level `kernel/patches/0001` through `0009` series preserves the full
research direction:

- request classification
- decode-read priority
- prefetch/prefill/evict scheduling
- request-shape and merge instrumentation
- io_uring and `RWF_*` hint plumbing
- ephemeral and recomputable semantics
- placement and lifetime metadata
- generic NVMe backend mapping ideas
- scheduler observability

That broader series exists for concept coverage and design continuity. It is
not the narrowest apply/compile target.

## Compile-Targeted Foundation Stack

The compile-targeted local kernel core lives in
`kernel/patches/foundation/`:

- `0001-kairo-request-classification.patch`
- `0002-kairo-mq-deadline-decode-priority.patch`
- `0003-kairo-prefetch-prefill-evict-policy.patch`
- `0004-kairo-mq-deadline-sysfs-counters.patch`

This smaller stack is the Linux 6.8.x-targeted foundation subset for the
current benchmark-driven kernel experiment.

## What The Foundation Includes

- shared request classification on `struct request`
- `ioprio` fallback for decode, prefetch, and prefill classification
- decode-read priority in `mq-deadline`
- prefetch deadline and budget handling
- prefill demotion accounting
- evict and discard accounting
- `mq-deadline` sysfs tunables and counters

## What The Foundation Excludes

The foundation subset intentionally excludes:

- Stage 3 merge shaping and request-size instrumentation
- Stage 4 `io_uring` and `RWF_*` hint plumbing
- Stage 5 ephemeral and recomputable semantics
- placement and lifetime metadata
- NVMe Streams, FDP, or ZNS mapping

Those areas remain in the broader RFC/POC architecture series.

## Linux 6.8.x Flow

Use the Linux 6.8 harness under
`kernel/integration/linux-6.8/`:

```bash
./scripts/validate_patch_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/apply_foundation_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/validate_foundation_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/build_foundation_objects.sh /path/to/linux-6.8.x
```

The scripts expect these kernel files to exist:

- `block/mq-deadline.c`
- `block/blk-mq.c`
- `include/linux/blk-mq.h`
- `include/linux/blk_types.h`

## Current Validation Status

See:

- [kernel/integration/linux-6.8/patch_apply_notes.md](/C:/Users/ManishKL/Documents/Playground/kv-io/kernel/integration/linux-6.8/patch_apply_notes.md)
- [docs/tested_kernel_matrix.md](/C:/Users/ManishKL/Documents/Playground/kv-io/docs/tested_kernel_matrix.md)

At the current repo state:

- foundation patch applicability has been checked on a local Linux 6.8.12 tree
- foundation patch application has been validated locally
- foundation symbol validation has been validated locally
- the requested combined `block/blk-mq.o block/mq-deadline.o` harness has been
  run locally and currently fails on a `blk-mq.o` tree issue outside the Kairo
  patch path
- the direct patched `block/mq-deadline.o` build has passed locally
- boot validation is still pending
- runtime sysfs visibility is still pending
- benchmark counter movement is still pending

This keeps the project honest about what has been implemented versus what has
actually been run.
