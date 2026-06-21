# Kairo Benchmark Design

## Goal

`kairo_bench` is intended to model the storage-facing behavior of AI inference KV-cache traffic without requiring a real GPU or model runtime. The benchmark focuses on how decode-critical reads interact with background cache creation and other competing I/O.

## Workload Model

The benchmark should simulate:

- prefill writes
- decode reads
- prefetch reads
- eviction and discard
- multi-model mixed traffic
- normal background I/O

The initial C implementation covers decode and prefill directly. `fio` profiles provide an additional path for mixed traffic experiments. Later revisions can add explicit prefetch and eviction workers to the C harness.

## How The Benchmark Approximates AI Inference

The benchmark does not attempt to execute attention kernels or generate tokens. Instead, it approximates the storage demand pattern created by inference:

- decode workers repeatedly issue reads against an existing cache region
- prefill workers issue writes that expand or refresh cache state
- prefetch behavior can be approximated by sequential reads ahead of the decode region
- eviction can be approximated by discard or overwrite activity on stale regions
- separate files or offset ranges stand in for independent sessions or models

This isolates the Linux storage path from GPU and model variability while preserving the key I/O relationships that Kairo cares about.

## `kairo_bench` Design

The baseline benchmark is a compilable C program that:

- accepts file path, file size, block size, thread counts, runtime, and queue-depth placeholder arguments
- opens the target file with `O_DIRECT` when possible
- allocates aligned buffers using `posix_memalign()`
- spawns decode reader threads and prefill writer threads
- measures per-read latency with `clock_gettime()`
- prints totals and simple read latency statistics at the end

The baseline intentionally uses `pthread`, `pread()`, and `pwrite()` so the workload is straightforward to build and reason about. A later phase can preserve the same workload model while moving submission to `io_uring`.

## Metrics

The benchmark plan should collect:

- decode read p50 latency
- decode read p95 latency
- decode read p99 latency
- prefetch latency
- write throughput
- aggregate SSD throughput
- queue depth
- IOPS
- merge rate if available
- CPU overhead
- tokens per second proxy
- time-to-first-token proxy

The first benchmark binary emits only a subset of these directly. The rest can come from `fio`, tracing, or operating-system tools during early experiments.

## Tokens-Per-Second Proxy

A simple proxy is:

```text
tokens_per_second_proxy = completed_decode_reads / runtime_seconds
```

This is not a model-level throughput measurement. It is a stable way to compare how often decode-like storage operations complete under different interference conditions.

## Time-To-First-Token Proxy

A simple proxy is:

```text
first_decode_completion_time - benchmark_start_time
```

Again, this is not a real model metric. It captures how quickly the storage path can satisfy the first decode-like request after the workload begins.

## Experimental Scenarios

Recommended baseline scenarios:

1. decode-only reads
2. decode reads plus background prefill writes
3. decode plus prefetch
4. multi-model mixed traffic using disjoint offsets or files
5. mixed KV traffic plus ordinary background I/O

Useful parameters to sweep:

- block size
- file size
- number of decode workers
- number of prefill workers
- queue-depth placeholder
- scheduler choice

## FIO Profiles

The repository includes:

- `kairo_decode_read.fio` for large-block read-dominant behavior
- `kairo_mixed_prefill_decode.fio` for mixed read and write interference
- `kairo_multimodel.fio` for multiple concurrent regions representing different models or sessions

These profiles should stay generic and file-backed so they can run on ordinary Linux systems.

## Validation Strategy

For every result, compare:

- baseline file-backed runs
- `none` scheduler when available
- baseline `mq-deadline`
- future KV-aware scheduler experiments

Supplement benchmark output with:

- `iostat`
- `lsblk`
- `fio` JSON output
- `perf` or `bpftrace` when deeper analysis is needed
- `debugfs` and `sysfs` counters when kernel changes are present

## Expected Outcome

The benchmark is successful if it can reproduce the central interference story:

- decode-critical reads suffer under competing write pressure on a generic Linux stack
- a KV-aware scheduler policy can reduce tail latency without collapsing write progress
