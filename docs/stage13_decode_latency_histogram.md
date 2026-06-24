# Stage 13: Decode Latency Histogram and Tail Estimator

## Why Tail Latency Needs Buckets

AI inference decode I/O is sensitive to tail latency. The 95th and 99th
percentiles of decode read latency directly affect Time-To-First-Token
(TTFT) and end-to-end inference latency. Average latency hides tail
behavior; maximum latency is too noisy.

A bucketed histogram provides:

- Memory-efficient sample aggregation (O(buckets) vs O(samples))
- Natural percentile estimation without sorting all samples
- Visibility into the full latency distribution, not just a single
  percentile or average
- Foundation for future adaptive controller policies that react to
  distribution shape shifts

## Why avg/max Is Not Enough

| Metric | Problem |
|--------|---------|
| Average | Hides tail — 99th percentile can be 10x the average |
| Maximum | Single outlier dominates; not statistically meaningful |
| P95/P99 from raw samples | Requires sorting O(n) samples per update cycle |

Bucketed histogram estimation gives production-acceptable p95/p99
precision with constant memory and CPU cost per update.

## How Bucketed p95/p99 Estimation Works

1. Each decode latency sample is mapped to one of 10 buckets:

| Bucket | Range (us) | Upper bound for estimation |
|--------|------------|---------------------------|
| 0_10US | 0–10 | 10 |
| 10_25US | 10–25 | 25 |
| 25_50US | 25–50 | 50 |
| 50_100US | 50–100 | 100 |
| 100_250US | 100–250 | 250 |
| 250_500US | 250–500 | 500 |
| 500_1000US | 500–1000 | 1000 |
| 1ms_2ms | 1000–2000 | 2000 |
| 2ms_5ms | 2000–5000 | 5000 |
| gt_5ms | >5000 | max_us |

2. Estimate p95: cumulative count from bucket 0 upward until
   `cumulative >= samples * 95 / 100`. Return the upper bound of that
   bucket. For the >5ms bucket, return `max_us`.

3. This gives a conservative upper-bound estimate. The true percentile
   is somewhere in the bucket's range.

## How This Strengthens Stage 10 Adaptive Controller

Stage 10's controller currently computes p95/p99 from a heuristic based
on avg and max. Stage 13 replaces that with histogram-based estimation:

- `observed_decode_avg_us` = `hist.sum_us / hist.samples`
- `observed_decode_p95_us` = `kairo_latency_histogram_estimate_percentile(hist, 95)`
- `observed_decode_p99_us` = `kairo_latency_histogram_estimate_percentile(hist, 99)`

If histogram samples are below `KAIRO_CTRL_MIN_SAMPLES`, the controller
remains observe-only and increments `controller_insufficient_samples`.

## WSL Validation Scope

The benchmark already collects decode latency samples from user space
(not from kernel completion hooks). Stage 13 adds histogram bucket
output derived from those user-space samples:

```
decode_lat_0_10us=42
decode_lat_10_25us=156
decode_lat_25_50us=331
...
```

This gives immediate validation value:

- Bucket counts are reproducible across runs
- P95/p99 from histogram estimation can be compared to true p95/p99
  from sorted samples
- The experiment script verifies parser output consistency

Stage 13 does **not** claim:

- Patched-kernel latency histogram movement unless a patched kernel
  is running
- Kernel-side call-site wiring (CONCEPTUAL-HOOK only)
- Better-than-avg/max accuracy in the kernel (needs completion hooks)

## What Remains Unvalidated in Kernel

- Completion-path histogram add call site (CONCEPTUAL-HOOK)
- Timer-based histogram reset for sliding-window estimation
- Histogram bucket boundary tuning for real NVMe devices
- Interaction with Stage 12 fairness (decode prioritization vs fair
  entity throttling)
- Tracepoint for histogram snapshot (future)
- Merged histogram across devices (currently per-device)

## Files

| File | Purpose |
|------|---------|
| `kernel/patches/0023-rfc-kairo-decode-latency-histogram.patch` | Kernel scaffold |
| `docs/stage13_decode_latency_histogram.md` | This document |
| `scripts/run_stage13_latency_histogram_experiment.sh` | Experiment script |
| `scripts/parse_stage13_latency_histogram_summary.py` | Summary parser |
| `scripts/collect_kairo_counters.sh` | Updated with histogram counters |
| `scripts/validate_patch_stack.sh` | Updated with Stage 13 checks |

## Patch 0023 Details

- Adds `enum kairo_decode_latency_bucket` with 10 buckets
- Adds `struct kairo_latency_histogram` with buckets, samples, sum_us,
  max_us, last_reset_ns
- Adds helpers: `kairo_latency_bucket_for_us()`, `kairo_latency_histogram_add()`,
  `kairo_latency_histogram_estimate_percentile()`, `kairo_latency_histogram_reset()`
- Integrates with Stage 10 controller via `dd_kairo_controller_update_from_hist()`
- Adds 10 histogram bucket sysfs counters, plus samples and max_us
- All integration points are CONCEPTUAL-HOOK
