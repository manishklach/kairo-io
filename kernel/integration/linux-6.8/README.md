# Kairo Linux 6.8 Foundation Harness

This directory contains the local validation harness for the Kairo Stage 1
foundation stack on Linux 6.8.x trees.

Kairo is an internal RFC/POC. These scripts are intended for local,
benchmark-driven validation on generic NVMe SSDs.

## Foundation Stack

The current compile-targeted foundation stack is:

- `0002-rfc-kairo-request-classification.patch`
- `0001-rfc-kairo-mq-deadline-decode-priority.patch`
- `0009-rfc-kairo-sysfs-debug-counters.patch`

This stage is meant to make request classification, decode-read scheduler
priority, and aligned sysfs counters coherent before moving deeper into later
RFC-only patches.

## Scripts

- `apply_kairo_patch.sh`
  - checks and applies the Stage 1 foundation patches in stack order
- `validate_patch.sh`
  - confirms the expected request-classification helpers, scheduler hooks, and
    sysfs counter symbols are present in the Linux tree
- `build_block_objects.sh`
  - runs `make olddefconfig`
  - attempts focused builds of `block/blk-mq.o` and `block/mq-deadline.o`

## Suggested Flow

```bash
./scripts/validate_patch_stack.sh
./kernel/integration/linux-6.8/apply_kairo_patch.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/validate_patch.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/build_block_objects.sh /path/to/linux-6.8.x
```

If the foundation stack builds and the patched kernel boots, continue with:

```bash
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```
