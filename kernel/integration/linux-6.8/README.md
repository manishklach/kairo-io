# Kairo Linux 6.8 Integration Harness

This directory contains the local validation harness for Kairo's experimental
`mq-deadline` patch on Linux 6.8.x trees.

Kairo is an internal RFC/POC. These scripts are intended for benchmark-driven
local validation on generic NVMe SSDs, not for upstream submission flow.

## Expected Inputs

- a Linux 6.8.x source tree path
- the Kairo repo checkout
- a local test machine where you can build kernel objects

## Scripts

- `apply_kairo_patch.sh`
  - runs `git apply --check` against the selected kernel tree
  - applies `kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch` on success
- `validate_patch.sh`
  - confirms the expected Kairo symbols are present in `block/mq-deadline.c`
- `build_block_objects.sh`
  - runs `make olddefconfig` and a focused `block/mq-deadline.o` build when possible
- `expected_sysfs.md`
  - documents the expected scheduler sysfs files after booting a patched kernel

## Suggested Flow

```bash
./kernel/integration/linux-6.8/apply_kairo_patch.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/validate_patch.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/build_block_objects.sh /path/to/linux-6.8.x
```

If the patch build succeeds and the patched kernel boots, continue with:

```bash
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```
