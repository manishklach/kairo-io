# Kairo

[![License](https://img.shields.io/badge/license-GPL--2.0-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/manishklach/kairo-io?display_name=tag&label=release)](https://github.com/manishklach/kairo-io/releases)
[![Last Commit](https://img.shields.io/github/last-commit/manishklach/kairo-io)](https://github.com/manishklach/kairo-io/commits/main)
[![Status](https://img.shields.io/badge/status-RFC%2FPOC-orange)](.)

**Kernel AI Runtime I/O for KV-cache-aware Linux storage**

Kairo is a Linux-kernel RFC/POC exploring a missing systems layer for AI inference: **storage I/O that understands KV-cache traffic, decode-critical reads, prefetch pressure, recomputable cache data, model/session locality, and backend placement intent.**

Modern AI inference is no longer just a GPU problem. Long-context models, agentic workloads, multi-session serving, KV-cache reuse, and flash-backed memory tiers are creating new storage traffic patterns that traditional block schedulers were not designed to distinguish. Today, much of this traffic still reaches the kernel as ordinary reads and writes.

Kairo asks a simple question:

> What if the Linux storage stack could understand AI inference I/O as a first-class workload?

This repository explores that question through kernel patches, benchmark tooling, tracepoint scaffolding, and Linux 6.8.x integration scripts.

---

## Why Kairo Exists

AI inference increasingly depends on memory objects that are:

* too large to keep entirely in HBM or DRAM,
* too valuable to treat as cold storage,
* latency-sensitive during decode,
* often session-scoped or model-scoped,
* frequently recomputable or short-lived,
* and increasingly backed by NVMe SSDs or flash memory tiers.

Traditional storage systems mostly see:

```text
read
write
discard
flush
```

AI runtimes know much more:

```text
decode-critical read
prefetch read
prefill write
eviction cleanup
session-local KV cache
model-local KV cache
recomputable cache
short-lived placement group
```

Kairo explores how that higher-level intent could flow into the Linux block layer and, eventually, into generic NVMe backend placement mechanisms.

---

## Core Idea

Kairo introduces a research path for classifying and scheduling AI inference I/O:

```text
AI runtime / benchmark
    -> hint path
    -> request classification
    -> mq-deadline scheduling policy
    -> semantic and placement metadata
    -> generic backend mapping scaffold
    -> tracepoint observability
```

The current implementation focuses on:

* decode-read prioritization under mixed read/write pressure,
* prefetch-aware scheduling,
* prefill-write and eviction demotion accounting,
* model/session/cache-pool/lifetime metadata,
* generic backend mapping scaffolds for Streams/FDP/ZNS-style placement,
* structured benchmark experiments,
* sysfs counters,
* and kernel tracepoint observability scaffolding.

---

## Project Status

Kairo is currently an **internal RFC/POC**.

It is not intended for LKML submission at this stage.

The repo contains two parallel tracks:

### 1. Compile-targeted Linux 6.8.x foundation stack

Located under:

```text
kernel/patches/foundation/
```

This is the smaller kernel-core subset intended for local Linux 6.8.x apply/build experiments.

It covers:

* request classification,
* `ioprio` fallback mapping,
* `mq-deadline` decode priority,
* prefetch deadline handling,
* prefill-write demotion accounting,
* eviction/discard accounting,
* and sysfs tunables/counters.

### 2. Broader RFC/POC architecture series

Located under:

```text
kernel/patches/
```

This preserves the full Kairo architecture direction, including:

* request classification,
* decode-read priority,
* prefetch/prefill/evict scheduling,
* request-shape and merge instrumentation,
* `io_uring` / `RWF_*` hint plumbing,
* ephemeral and recomputable cache semantics,
* model/session/lifetime placement metadata,
* generic NVMe backend mapping hooks,
* tracepoint observability,
* recompute-aware eviction policy,
* KV-cache residency heatmap tracking,
* and KV admission control for flash-backed storage.

## Current Validation Snapshot

Kairo includes a WSL-friendly validation runner:

```bash
./scripts/run_wsl_validation_snapshot.sh
```

This checks repository consistency, benchmark build, experiment harness
dry-runs, and optional user-space benchmark smoke tests. It does not claim
patched-kernel runtime validation.

Latest snapshot:

* [docs/validation_snapshot.md](docs/validation_snapshot.md)

---

## Why This Matters

Kairo targets a real emerging systems problem:

> AI inference workloads are beginning to use storage as an active memory tier, but the kernel still lacks AI-aware request semantics.

Without richer I/O classification, the block layer cannot easily distinguish:

```text
A decode-critical KV-cache read
from
A background prefill write
from
A recomputable cache eviction
from
An ordinary durable application write
```

That distinction matters because decode latency can dominate perceived inference latency. If decode reads are delayed behind background writes, eviction cleanup, or poorly shaped prefetch traffic, the storage tier becomes part of the inference tail-latency problem.

Kairo explores whether Linux can expose a better path.

---

## Architecture

```text
+------------------------------------------------------------------+
| AI Runtime / Synthetic Benchmark                                 |
|                                                                  |
|  - decode reads                                                   |
|  - prefetch reads                                                 |
|  - prefill writes                                                 |
|  - eviction / discard                                             |
|  - model, session, cache-pool, lifetime metadata                  |
+------------------------------------------------------------------+
                         |
                         v
+------------------------------------------------------------------+
| User-Space Hint Path                                             |
|                                                                  |
|  - ioprio fallback                                                |
|  - O_DIRECT                                                       |
|  - io_uring / RWF_* scaffold                                      |
|  - semantic hints: ephemeral, recomputable, avoid-pagecache       |
+------------------------------------------------------------------+
                         |
                         v
+------------------------------------------------------------------+
| Kairo Block-Layer Metadata                                       |
|                                                                  |
|  - request classification                                         |
|  - decode / prefetch / prefill / evict classes                    |
|  - model_id / session_id / cache_pool_id                          |
|  - lifetime_class / recompute_ok                                  |
|  - backend placement intent                                       |
+------------------------------------------------------------------+
                         |
                         v
+------------------------------------------------------------------+
| Kairo-Aware Scheduling                                           |
|                                                                  |
|  - decode-critical read priority                                  |
|  - prefetch deadline and budget handling                          |
|  - prefill-write demotion                                         |
|  - eviction/discard demotion                                      |
|  - starvation accounting                                          |
+------------------------------------------------------------------+
                         |
                         v
+------------------------------------------------------------------+
| Generic NVMe Backend Mapping Scaffold                            |
|                                                                  |
|  - backend class mapping                                          |
|  - no-op fallback                                                 |
|  - Streams/FDP/ZNS-style hook locations                           |
|  - no physical placement claimed yet                              |
+------------------------------------------------------------------+
                         |
                         v
+------------------------------------------------------------------+
| Observability                                                    |
|                                                                  |
|  - sysfs counters                                                 |
|  - benchmark summaries                                            |
|  - tracepoint scaffold                                            |
|  - bpftrace/ftrace analysis scripts                               |
+------------------------------------------------------------------+
```

---

## Kernel Patch Tracks

### Compile-targeted foundation stack

```text
kernel/patches/foundation/
  0001-kairo-request-classification.patch
  0002-kairo-mq-deadline-decode-priority.patch
  0003-kairo-prefetch-prefill-evict-policy.patch
  0004-kairo-mq-deadline-sysfs-counters.patch
```

Use this path for local Linux 6.8.x apply/build experiments.

### Full RFC/POC architecture series

```text
kernel/patches/
  0001-rfc-kairo-mq-deadline-decode-priority.patch
  0002-rfc-kairo-request-classification.patch
  0003-rfc-kairo-io-uring-hint-plumbing.patch
  0004-rfc-kairo-large-block-coalescing.patch
  0005-rfc-kairo-prefetch-deadline-hints.patch
  0006-rfc-kairo-ephemeral-cache-semantics.patch
  0007-rfc-kairo-placement-lifetime-hints.patch
  0008-rfc-kairo-nvme-zns-fdp-mapping.patch
  0009-rfc-kairo-sysfs-debug-counters.patch
  0010-rfc-kairo-request-classification-real.patch
  0011-rfc-kairo-write-antistarvation-deadline.patch
  0012-rfc-kairo-nvme-tag-reservation.patch
  0013-rfc-kairo-mq-deadline-dispatch-O1.patch
  0014-rfc-kairo-io-uring-sqe-hint-flag.patch
  0015-rfc-kairo-merge-bias-real.patch
  0016-rfc-kairo-bpf-dispatch-hook.patch
  0017-rfc-kairo-tracepoints-observability.patch
  0018-rfc-kairo-adaptive-latency-controller.patch
  0020-rfc-kairo-model-session-fairness.patch
  0022-rfc-kairo-foundation-tracepoints-linux-6.8.patch
  0023-rfc-kairo-decode-latency-histogram.patch
  0024-rfc-kairo-controller-feedback-wiring.patch
  0025-rfc-kairo-fairness-accounting-sysfs.patch
  0026-rfc-kairo-blkcg-ai-io-controller.patch
  0027-rfc-kairo-io-uring-kv-region-hints.patch
  0028-rfc-kairo-recompute-aware-eviction.patch
  0029-rfc-kairo-kv-residency-heatmap.patch
  0030-rfc-kairo-kv-admission-control.patch
```

This broader series is the architecture map. Not every patch in this track is compile-targeted yet, and numbering intentionally has gaps where intermediate local RFC ideas were not retained in the repo.

---

## Current Stages

| Stage | Scope | Patch / Track | State |
| --- | --- | --- | --- |
| Foundation | Linux 6.8.x compile-targeted subset | foundation `0001`-`0005` | locally apply/build validated |
| Stage 6 | model/session/lifetime placement experiments | `0007`, `0009` | implemented in benchmark and harness |
| Stage 7 | generic NVMe backend mapping scaffold | `0008`, `0009` | implemented as generic mapping scaffold |
| Stage 7.5 | NVMe hook audit and risk classification | `0008` rewrite + audit docs/scripts | implemented |
| Stage 8 | observability and trace scaffolding | `0017` | scaffolded in broad RFC/POC series |
| Stage 9 | WSL validation snapshot packaging | tooling only | implemented |
| Stage 10 | adaptive latency controller | `0018` | partially implemented, partially conceptual |
| Stage 11 | Linux 6.8 foundation tracepoints | foundation `0005`, broad `0022` | compile-targeted foundation path |
| Stage 12 | model/session fairness scheduler | `0020` | conceptual scheduler scaffold |
| Stage 13 | decode latency histogram | `0023` | histogram scaffold + experiment tooling |
| Stage 14 | controller feedback wiring | `0024` | partial compile-target helpers + conceptual dispatch hook |
| Stage 15 | fairness accounting and sysfs wiring | `0025` | conceptual wiring + experiment tooling |
| Stage 16 | blk-cgroup AI I/O controller | `0026` | conceptual blkcg scaffold + experiment tooling |
| Stage 17 | io_uring KV region hints | `0027` | conceptual io_uring region scaffold + experiment tooling |
| Stage 18 | recompute-aware eviction scheduler | `0028` | conceptual eviction class/score scaffold + experiment tooling |
| Stage 19 | KV residency heatmap | `0029` | conceptual hot/warm/cold/evictable tracking + experiment tooling |
| Stage 20 | flash-backed KV admission control | `0030` | conceptual admission policy scaffold + experiment tooling |

For the detailed tracker, use:

* [docs/full_architecture_status.md](docs/full_architecture_status.md)
* [docs/implementation_stages.md](docs/implementation_stages.md)
* [docs/tested_kernel_matrix.md](docs/tested_kernel_matrix.md)

---

## Advanced Feature Map

| Area | Implemented Today | Still Experimental / Conceptual |
| --- | --- | --- |
| Decode-read prioritization | foundation stack + broad RFC patches | broader multi-stage tuning is still benchmark-driven |
| Request classification | base classification (`0002`) plus real request-init path (`0010`) | full runtime hint plumbing beyond current paths |
| Prefetch / prefill / evict policy | foundation stack policy and accounting | scheduler refinements under later stages |
| Write anti-starvation | `0011` scaffolded in broad RFC/POC series | runtime validation on patched kernel pending |
| Tag reservation | `0012` broad series patch | patched-kernel validation pending |
| O(1) dispatch path | `0013` broad series patch | patched-kernel validation pending |
| Merge bias / request shaping | `0004` foundation instrumentation + `0015` broad-series merge path | impact on real NVMe traffic still unvalidated |
| `io_uring` hints | `0014` SQE flag and `0027` region-hint scaffold | end-to-end kernel plumbing remains experimental |
| Recompute-aware eviction | `0028` eviction class/score scaffold | dispatch-path eviction integration remains conceptual |
| KV residency heatmap | `0029` heat class/tracking scaffold | fixed-array linear scan is RFC-only; no periodic decay timer wired |
| KV admission control | `0030` admission policy scaffold | decode-p99 feedback and per-cgroup budgets remain conceptual |
| Ephemeral / recomputable semantics | user/kernel hint scaffolds | no production ABI claimed |
| Placement / lifetime metadata | benchmark-visible and metadata-visible | physical device placement not claimed |
| Generic NVMe backend mapping | benchmark-visible generic mapping scaffold | real Streams/FDP/ZNS placement unvalidated |
| Tracepoints and tracing tools | Stage 8/11 trace scaffolds, parsers, `bpftrace` helpers | stable ABI and patched-kernel availability not claimed |
| Adaptive controller | Stage 10 control policy and sysfs scaffold | decode latency observation path remains incomplete |
| Fairness and tenant isolation | Stage 12/15 fairness scaffolds | real scheduler enforcement remains conceptual |
| blk-cgroup AI controller | Stage 16 experiment scaffold | cgroup interface and dispatch hooks remain conceptual |

---

## Benchmark

The benchmark lives at:

```text
bench/kairo_bench.c
```

It models AI inference-like I/O using:

* decode workers,
* prefetch workers,
* prefill/write workers,
* eviction workers,
* multi-session mode,
* model/session/cache-pool/lifetime metadata,
* backend-mode modeling,
* and latency/throughput summaries.

Build:

```bash
make
```

or:

```bash
gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c
```

---

## Temporary Hint Mapping

The current foundation path uses `ioprio` as a practical local signal:

```text
RT prio 0 read   -> decode-critical read
RT prio 1 read   -> prefetch read
BE prio 7 write  -> prefill/background write
discard/zeroes   -> eviction cleanup
```

This is intentionally temporary. The broader RFC path also explores `io_uring` and `RWF_*` hint propagation.

---

## Running Experiments

### Baseline

```bash
./scripts/run_baseline.sh /mnt/nvme/kairo.test nvme0n1
```

### Kairo POC

```bash
./scripts/set_mq_deadline.sh nvme0n1
./scripts/run_kairo_poc.sh /mnt/nvme/kairo.test nvme0n1
```

### A/B comparison

```bash
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Multisession workload

```bash
./scripts/run_multisession_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 6 placement/lifetime experiment

```bash
./scripts/run_stage6_placement_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 7 backend mapping experiment

```bash
./scripts/run_stage7_backend_mapping_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 8 trace experiment

```bash
./scripts/run_stage8_trace_experiment.sh /mnt/nvme/kairo.test nvme0n1 --trace-mode none
```

On an unpatched kernel, trace experiments should still run and report tracepoint availability honestly.

### Stage 10 adaptive controller experiment

```bash
./scripts/run_stage10_latency_controller_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 11 foundation trace experiment

```bash
./scripts/run_stage11_foundation_trace_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 12 fairness experiment

```bash
./scripts/run_stage12_fairness_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 13 decode histogram experiment

```bash
./scripts/run_stage13_latency_histogram_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 14 controller feedback experiment

```bash
./scripts/run_stage14_controller_feedback_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 15 fairness accounting experiment

```bash
./scripts/run_stage15_fairness_accounting_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 16 blk-cgroup AI controller experiment

```bash
./scripts/run_stage16_blkcg_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 17 io_uring KV region experiment

```bash
./scripts/run_stage17_io_uring_region_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 18 recompute-aware eviction experiment

```bash
./scripts/run_stage18_recompute_eviction_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 19 KV heatmap experiment

```bash
./scripts/run_stage19_kv_heatmap_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

### Stage 20 KV admission control experiment

```bash
./scripts/run_stage20_kv_admission_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

---

## Success Metrics

Primary metric:

```text
decode_p99_us under mixed prefill-write pressure
```

Secondary metrics:

```text
decode_p95_us
decode_avg_us
decode_read_MBps
prefetch_read_MBps
write_MBps
eviction behavior
starvation escapes
backend mapping counters
tracepoint event counts
```

The goal is not just higher throughput. The key question is whether decode-critical I/O can be protected when background AI cache traffic competes for the same storage path.

---

## Linux 6.8 Foundation Validation

Use the Linux 6.8 integration harness:

```bash
./kernel/integration/linux-6.8/apply_foundation_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/validate_foundation_stack.sh /path/to/linux-6.8.x
./kernel/integration/linux-6.8/build_foundation_objects.sh /path/to/linux-6.8.x
```

Smoke check:

```bash
./kernel/integration/linux-6.8/smoke_foundation_stack.sh /path/to/linux-6.8.x --check-only
```

NVMe hook audit:

```bash
./kernel/integration/linux-6.8/audit_nvme_hooks.sh /path/to/linux-6.8.x --stdout
```

Tracepoint audit:

```bash
./kernel/integration/linux-6.8/audit_tracepoints.sh /path/to/linux-6.8.x --stdout
```

---

## Validation Path

Tracked validation lives in:

* [docs/tested_kernel_matrix.md](docs/tested_kernel_matrix.md)
* [docs/full_architecture_status.md](docs/full_architecture_status.md)
* [docs/validation_snapshot.md](docs/validation_snapshot.md)
* [docs/kernel_foundation_stack.md](docs/kernel_foundation_stack.md)
* [docs/kernel_foundation_invariants.md](docs/kernel_foundation_invariants.md)

Primary validation entry points:

```bash
./scripts/run_wsl_validation_snapshot.sh
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

Current status, at a high level:

```text
Foundation patch apply:       locally validated on Linux 6.8.x path
Foundation symbol validation: locally validated
mq-deadline object build:     locally validated
blk-mq object build:          not yet cleanly validated in matrix
Boot validation:              pending
Runtime sysfs visibility:     pending
Benchmark counter movement:     pending
Stage 8-20 harnesses:         implemented, but mostly dry-run/user-space validated
Full RFC series compile:      not claimed
```

Kairo intentionally separates what is implemented, what is scaffolded, and what is validated. This repo is an internal RFC/POC and benchmark-driven prototype, not a claim that the full Stage 10-17 kernel path has been boot-tested or benchmark-validated on patched generic NVMe SSDs.

---

## Documentation

Key docs:

* [docs/architecture.md](docs/architecture.md)
* [docs/implementation_stages.md](docs/implementation_stages.md)
* [docs/full_architecture_status.md](docs/full_architecture_status.md)
* [docs/patch_series.md](docs/patch_series.md)
* [docs/kernel_foundation_stack.md](docs/kernel_foundation_stack.md)
* [docs/kernel_foundation_invariants.md](docs/kernel_foundation_invariants.md)
* [docs/stage6_model_session_lifetime.md](docs/stage6_model_session_lifetime.md)
* [docs/stage7_generic_nvme_backend_mapping.md](docs/stage7_generic_nvme_backend_mapping.md)
* [docs/stage7_5_nvme_hook_audit.md](docs/stage7_5_nvme_hook_audit.md)
* [docs/stage8_kernel_observability.md](docs/stage8_kernel_observability.md)
* [docs/stage10_adaptive_latency_controller.md](docs/stage10_adaptive_latency_controller.md)
* [docs/stage11_foundation_tracepoints.md](docs/stage11_foundation_tracepoints.md)
* [docs/stage12_model_session_fairness.md](docs/stage12_model_session_fairness.md)
* [docs/stage13_decode_latency_histogram.md](docs/stage13_decode_latency_histogram.md)
* [docs/stage14_controller_feedback_wiring.md](docs/stage14_controller_feedback_wiring.md)
* [docs/stage15_fairness_accounting_sysfs.md](docs/stage15_fairness_accounting_sysfs.md)
* [docs/stage16_blkcg_ai_io_controller.md](docs/stage16_blkcg_ai_io_controller.md)
* [docs/stage17_io_uring_kv_region_hints.md](docs/stage17_io_uring_kv_region_hints.md)
* [docs/stage18_recompute_aware_eviction.md](docs/stage18_recompute_aware_eviction.md)
* [docs/stage19_kv_residency_heatmap.md](docs/stage19_kv_residency_heatmap.md)
* [docs/stage20_kv_admission_control.md](docs/stage20_kv_admission_control.md)
* [docs/validation_snapshot.md](docs/validation_snapshot.md)
* [docs/tested_kernel_matrix.md](docs/tested_kernel_matrix.md)

---

## Repository Layout

```text
bench/                         Synthetic KV-cache I/O benchmark
docs/                          Architecture and validation documentation
include/                       User-space Kairo hint definitions
kernel/patches/                Broad RFC/POC kernel patch series
kernel/patches/foundation/     Compile-targeted Linux 6.8.x foundation stack
kernel/integration/linux-6.8/  Apply/build/audit helpers for Linux 6.8.x
scripts/                       Benchmark, validation, parsing, and tracing tools
scripts/bpftrace/              bpftrace helpers for Kairo tracepoint experiments
```

---

## What Kairo Is Not

Kairo is not:

* a production kernel subsystem,
* a stable userspace ABI,
* an LKML-ready patch series,
* a vendor-specific SSD integration,
* or a claim of physical NVMe placement today.

Kairo is a research-grade kernel/storage prototype for exploring what AI-aware Linux storage could become.

---

## Design Principles

Kairo follows several principles:

```text
Generic before vendor-specific.
Observable before opaque.
Benchmark-driven before claims.
No-op fallback before unsafe behavior.
Foundation stack separate from architecture scaffolds.
Explicit validation status instead of overclaiming.
```

---

## License

Kairo is licensed under [GPL-2.0-only](LICENSE) to stay aligned with the Linux kernel-facing patch workflow in this RFC/POC repository.
