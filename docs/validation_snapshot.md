# Kairo Validation Snapshot

Date: 20260624-094610
Environment: WSL
Kernel: 6.6.87.2-microsoft-standard-WSL2+
WSL: true

## Summary

| Check | Result |
|---|---|
| validate_patch_stack | pass |
| make | pass |
| fallback_gcc_build | not_needed |
| benchmark_exists | true |
| stage6_dryrun | pass |
| stage7_dryrun | pass |
| stage8_dryrun | pass |
| stage13_dryrun | pass |
| stage14_dryrun | pass |
| stage15_dryrun | pass |
| stage16_dryrun | pass |
| stage17_dryrun | pass |
| stage18_dryrun | pass |
| user_bench_baseline | skipped |
| user_bench_mixed | skipped |

## What This Validates

- repository consistency
- benchmark build
- experiment harness dry-run path
- WSL user-space benchmark smoke path

## What This Does Not Validate

- custom kernel boot
- Kairo sysfs counters
- mq-deadline patched-kernel behavior
- physical NVMe placement
- tracepoint availability on patched kernel

## Artifacts

- environment.log
- validate_patch_stack.log
- make.log
- stage6_dryrun.log
- stage7_dryrun.log
- stage8_dryrun.log
- stage13_dryrun.log
- stage14_dryrun.log
- stage15_dryrun.log
- stage16_dryrun.log
- stage17_dryrun.log
- stage18_dryrun.log
- user_bench_baseline.log
- user_bench_mixed.log

Results directory: `results/validation/20260624-094610`

Notes: WSL validation only; no custom kernel boot, no Kairo sysfs counters, no physical NVMe placement validation.
