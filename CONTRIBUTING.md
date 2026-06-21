# Contributing

Kairo is an internal Linux-kernel RFC/POC for AI KV-cache-aware block I/O.
Contributions should stay benchmark-driven, explicit about what has and has not
been validated, and narrowly scoped per change.

## Kernel Version Requirements

- the local foundation harness targets Linux `6.8.x`
- CI is pinned to Linux `6.8.12` for patch apply checks
- `docs/tested_kernel_matrix.md` is the source of truth for what has actually been applied, built, booted, and benchmarked

If you validate on a different `6.8.x` tree, add a new row instead of folding it into an existing claim.

## Local Build

Build the benchmark harness:

```bash
gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c
```

Or use:

```bash
./scripts/build_bench.sh
```

## Apply And Test Patches Locally

Start with repo-level patch checks:

```bash
./scripts/validate_patch_stack.sh
```

For the current Stage 1 foundation stack on a Linux `6.8.x` tree:

```bash
./kernel/integration/linux-6.8/apply_kairo_patch.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/validate_patch.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/build_block_objects.sh /path/to/linux-6.8.x
```

That flow currently targets:

- `0002-rfc-kairo-request-classification.patch`
- `0001-rfc-kairo-mq-deadline-decode-priority.patch`
- `0009-rfc-kairo-sysfs-debug-counters.patch`

Later-stage patches are still scaffold-heavy and should not be described as boot-validated unless you actually ran that validation.

## Runtime Validation

Use the runtime validator on a patched kernel:

```bash
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
```

What to look for:

- scheduler state should show `mq-deadline` as active
- required Kairo sysfs files must exist under `/sys/block/<dev>/queue/iosched/`
- the script prints before/after snapshots plus:
  - `kairo_decode_dispatches_delta`
  - `kairo_normal_dispatches_delta`
  - `kairo_starvation_escapes_delta`

How to interpret results:

- non-zero `kairo_decode_dispatches_delta` means the decode path was hit during the run
- zero `kairo_decode_dispatches_delta` means the script could not prove decode-path dispatch activity
- missing sysfs files or inability to select `mq-deadline` means the runtime validation did not actually reach the intended kernel path

For A/B comparisons, use:

```bash
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

## Contribution Expectations

- keep PRs focused; separate unrelated changes
- include the exact commands you ran and the real output you observed
- do not invent benchmark numbers
- do not claim kernel boot, sysfs, runtime, or benchmark validation unless you actually ran it
- when editing `kernel/patches/*.patch`, follow the repo’s implement-then-validate cycle and update the tracker docs carefully
- preserve the repo’s current positioning: internal RFC/POC, experimental kernel path, not intended for LKML submission at this stage

If a change only affects documentation or workflow scaffolding, say so plainly in the PR.
