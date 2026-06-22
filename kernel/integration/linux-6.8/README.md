# Kairo Linux 6.8 Foundation Harness

This directory contains the local Linux 6.8.x integration harness for the
compile-targeted Kairo foundation stack.

Kairo is an internal RFC/POC and research prototype. These scripts are for
local validation of an experimental kernel path on generic NVMe SSDs. They are
not intended as LKML submission tooling.

## Foundation Stack

The compile-targeted foundation subset lives in
`kernel/patches/foundation/`:

- `0001-kairo-request-classification.patch`
- `0002-kairo-mq-deadline-decode-priority.patch`
- `0003-kairo-prefetch-prefill-evict-policy.patch`
- `0004-kairo-mq-deadline-sysfs-counters.patch`

The broader `kernel/patches/0001` through `0009` series remains in place as
the larger RFC/POC architecture track. The `foundation/` subset is the apply
and compile target for Linux 6.8.x.

## Scripts

- `apply_foundation_stack.sh`
  - verifies the Linux tree path and required files
  - requires a Linux git checkout before applying patches
  - refuses dirty trees unless `--force` is passed
  - runs `git apply --check` for every foundation patch
  - supports `--check-only` for a non-mutating dry run
  - applies the stack only if every check succeeds
- `validate_foundation_stack.sh`
  - reports the Linux tree commit when available
  - checks that the expected Kairo symbols exist in the patched Linux tree
- `build_foundation_objects.sh`
  - reports the Linux tree commit when available
  - supports `--check-only` to print the local build path
  - runs `make olddefconfig`
  - first attempts `block/blk-mq.o block/mq-deadline.o`
  - reports fallback commands clearly if the local Linux tree rejects that path
- `smoke_foundation_stack.sh`
  - chains the metadata checks, dry-run apply checks, optional symbol
    validation, and optional object build into one non-mutating smoke test
- `patch_apply_notes.md`
  - records the local Linux 6.8 validation path and actual outcomes

## Suggested Flow

```bash
./scripts/validate_patch_stack.sh
./kernel/integration/linux-6.8/smoke_foundation_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/apply_foundation_stack.sh --check-only /path/to/linux-6.8.x
./kernel/integration/linux-6.8/validate_foundation_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/build_foundation_objects.sh --check-only /path/to/linux-6.8.x
```

If the patched kernel later boots successfully, continue with the runtime and
benchmark validators:

```bash
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

See [expected_sysfs.md](expected_sysfs.md)
for the expected scheduler files once the patched kernel is booted and
`mq-deadline` is selected.
