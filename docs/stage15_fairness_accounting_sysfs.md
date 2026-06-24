# Stage 15: Fairness Accounting and Sysfs Visibility

## Why Fairness Needs Sysfs Visibility

Stage 12 introduced the fairness data structures and conceptual policy
hooks, but left sysfs as scaffold comments only. Without sysfs:

- Fairness state is invisible during runtime
- Credits and thresholds cannot be tuned without recompiling
- Counter movement cannot be observed or validated
- The fairness policy is a black box

Stage 15 wires all 5 tunables and 7 counters into the mq-deadline
sysfs tree, making fairness visible and controllable.

## Tunables

| Name | Type | Default | Bounds | Description |
|------|------|---------|--------|-------------|
| `kairo_fairness_enable` | write | 0 | 0/1 | Enable fairness scheduling |
| `kairo_model_decode_credit` | write | 1000 | 1..100000 | Per-model decode credit pool |
| `kairo_session_decode_credit` | write | 100 | 1..100000 | Per-session decode credit pool |
| `kairo_fairness_refill_ms` | write | 1000 | 1..60000 | Credit refill interval in ms |
| `kairo_noisy_session_threshold` | write | 10000 | 1..1000000 | Decode dispatch threshold for noise detection |

All tunables have show and store functions with input validation and
bounds checking.

## Counters

| Name | Type | Description |
|------|------|-------------|
| `kairo_fairness_refills` | RO | Total credit refill events |
| `kairo_fairness_model_throttles` | RO | Model entity throttling events |
| `kairo_fairness_session_throttles` | RO | Session entity throttling events |
| `kairo_noisy_session_events` | RO | Noisy session detections |
| `kairo_protected_decode_dispatches` | RO | Decode dispatches preserved by fairness |
| `kairo_prefetch_fairness_throttles` | RO | Prefetch dispatches throttled by fairness |
| `kairo_write_fairness_demotions` | RO | Write demotions caused by fairness pressure |

## Accounting Semantics

Counters are event observations:

| Counter | Hook | When Incremented |
|---------|------|------------------|
| `fairness_refills` | `kairo_fairness_refill_if_needed()` | Every refill cycle |
| `protected_decode_dispatches` | `kairo_fairness_allow_decode()` | When credit > 0 and decode proceeds |
| `fairness_session_throttles` | `kairo_fairness_allow_decode()` | When credit == 0 and decode blocked |
| `fairness_model_throttles` | `kairo_fairness_lookup_entity()` | When model entity throttled |
| `prefetch_fairness_throttles` | `kairo_fairness_throttle_prefetch()` | When prefetch throttled |
| `write_fairness_demotions` | `kairo_fairness_demote_write()` | When write demoted |
| `noisy_session_events` | `kairo_fairness_account_dispatch()` | Every 100 dispatches above threshold |

A single request may increment multiple counters if it passes through
multiple hooks (e.g., decode allowed but later write from same session
is demoted). Counters are NOT unique request counts.

## Noisy Session Benchmark

The benchmark `kairo_bench.c` supports:

```
--noisy-session <id>       Session ID for noise stress test
--noisy-model <id>         Model ID for noise stress test
--noisy-multiplier <n>     Traffic multiplier for noisy entity
```

When noisy flags are set, the benchmark prints:

```
noisy_session=<id>
noisy_model=<id>
noisy_multiplier=<n>
fairness_mode=stress
```

Without noisy flags:

```
fairness_mode=none
```

The benchmark does **not** fake kernel fairness state. All fairness
counters require a patched kernel.

## WSL Limitations

WSL can validate:
- Experiment script dry-run (all 5 cases)
- Parser output format
- Benchmark noisy field output
- Script counter collection format

WSL cannot validate:
- Patched-kernel fairness counter movement
- Credit tracking and refill
- Noisy session detection
- Throttle/demote behavior

Stage 15 does **not** claim kernel fairness counter movement unless
a patched kernel is running.

## Files

| File | Purpose |
|------|---------|
| `kernel/patches/0025-rfc-kairo-fairness-accounting-sysfs.patch` | Kernel scaffold |
| `docs/stage15_fairness_accounting_sysfs.md` | This document |
| `scripts/run_stage15_fairness_accounting_experiment.sh` | Experiment script |
| `scripts/parse_stage15_fairness_accounting_summary.py` | Summary parser |
| `scripts/collect_kairo_counters.sh` | Updated with fairness counters |
| `scripts/validate_patch_stack.sh` | Updated with Stage 15 checks |
