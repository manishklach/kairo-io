# Stage 8: Kairo Kernel Observability and Tracepoints

## Objective

Add an RFC/POC tracepoint scaffolding layer for the full Kairo request
lifecycle: classification, scheduler decisions, dispatch, demotion, merge,
semantic flags, placement metadata, and backend mapping.

Stage 8 does **not** claim stable tracing ABI, LKML readiness, or
production instrumentation. It is a local kernel research scaffold.

## Why Counters Are Not Enough

Kairo already has sysfs counters (`kairo_decode_dispatches`,
`kairo_prefetch_dispatches`, etc.) and benchmark summary output.
Counters tell us:

- How many decode dispatches happened
- How many prefetch dispatches happened
- How many no-op backend fallbacks occurred

Counters do **not** tell us:

- The latency distribution of individual decode dispatches
- The relationship between scheduler decisions and dispatch outcomes
- The per-request metadata flow from classification to backend mapping
- Why a specific merge decision was made
- Whether semantic flags are actually reaching the block layer
- The request lifecycle across a specific model/session/cache-pool

Tracepoints fill this gap by recording per-event payloads at each
lifecycle stage.

## Kairo Request Lifecycle

```
userspace hint (ioprio / RWF_KAIRO_*)
  |
  v
kiocb metadata (Stage 4)
  |
  v
bio metadata
  |
  v
request metadata (Stage 1/2)
  |
  +---> kairo_request_classified
  |
  v
mq-deadline scheduler decision (Stage 1/2)
  |
  +---> kairo_scheduler_decision
  |
  v
dispatch path
  |
  +---> kairo_decode_dispatch (if decode)
  +---> kairo_prefetch_dispatch (if prefetch)
  +---> kairo_write_demoted (if prefill/evict demoted)
  |
  v
merge/coalescing observation (Stage 3)
  |
  +---> kairo_merge_decision
  |
  v
semantic flag propagation (Stage 5)
  |
  +---> kairo_semantic_classified
  |
  v
placement/lifetime metadata (Stage 6)
  |
  +---> kairo_placement_classified
  |
  v
backend mapping (Stage 7)
  |
  +---> kairo_backend_mapped
```

## Proposed Tracepoints and Payloads

| Tracepoint | Stage | Key Fields | Compile Risk |
|------------|-------|------------|-------------|
| `kairo_request_classified` | 1 | dev, sector, nr_bytes, op, ioprio, io_class, hint_source, flags | medium |
| `kairo_scheduler_decision` | 2 | dev, sector, nr_bytes, io_class, decision, reason, budget_used, deadline_ns | low |
| `kairo_decode_dispatch` | 2 | dev, sector, nr_bytes, budget_used, latency_hint_ns | low |
| `kairo_prefetch_dispatch` | 2 | dev, sector, nr_bytes, budget_used, deadline_ns, deadline_near | low |
| `kairo_write_demoted` | 2 | dev, sector, nr_bytes, io_class, reason, starvation_escape | low |
| `kairo_merge_decision` | 3 | dev, sector, nr_bytes, io_class, merge_attempted, merge_success, reason | conceptual |
| `kairo_semantic_classified` | 5 | dev, sector, nr_bytes, ephemeral, recomputable, avoid_pagecache, no_strong_durability | conceptual |
| `kairo_placement_classified` | 6 | dev, sector, nr_bytes, model_id, session_id, cache_pool_id, placement_group, lifetime_class, recompute_ok | low |
| `kairo_backend_mapped` | 7 | dev, sector, nr_bytes, backend_class, stream_id, fdp_placement_id, zone_hint, noop_fallback, flags | low |

## How ftrace Would Be Used

```bash
# Enable all Kairo tracepoints
echo 1 > /sys/kernel/tracing/events/kairo/enable

# Capture trace
cat /sys/kernel/tracing/trace_pipe > /tmp/kairo_trace.log

# Run benchmark, then disable
echo 0 > /sys/kernel/tracing/events/kairo/enable
```

The stage 8 experiment script (`scripts/run_stage8_trace_experiment.sh`)
automates this workflow for ftrace and bpftrace.

## How bpftrace Scripts Would Be Used

```bash
# Track decode/prefetch dispatch latency and bytes
bpftrace scripts/bpftrace/kairo_latency.bt

# Show scheduler decisions by io_class
bpftrace scripts/bpftrace/kairo_dispatch.bt

# Show Stage 7 backend mapping outcomes
bpftrace scripts/bpftrace/kairo_backend.bt
```

## Stage 8 Components

| Component | Type | Description |
|-----------|------|-------------|
| `0017-rfc-kairo-tracepoints-observability.patch` | patch | Adds tracepoint header, instrumentation stubs, and enum comments |
| `include/trace/events/kairo.h` | new header | TRACE_EVENT definitions for 9 tracepoints |
| `scripts/bpftrace/kairo_latency.bt` | bpftrace | Dispatch latency and byte-count tracking |
| `scripts/bpftrace/kairo_dispatch.bt` | bpftrace | Scheduler decision breakdown |
| `scripts/bpftrace/kairo_backend.bt` | bpftrace | Backend mapping outcome tracking |
| `docs/stage8_kernel_observability.md` | doc | This document |
| `kernel/integration/linux-6.8/audit_tracepoints.sh` | audit | Checks Linux 6.8 tree for tracepoint infrastructure |
| `scripts/run_stage8_trace_experiment.sh` | experiment | Runs benchmark with ftrace/bpftrace capture |
| `scripts/parse_stage8_trace_log.py` | parser | Parses trace logs into structured summary |

## How Stage 8 Connects Stage 1 Through Stage 7

- **Stage 1 (classification)** → `kairo_request_classified`
- **Stage 2 (scheduling)** → `kairo_scheduler_decision`,
  `kairo_decode_dispatch`, `kairo_prefetch_dispatch`,
  `kairo_write_demoted`
- **Stage 3 (merge)** → `kairo_merge_decision`
- **Stage 5 (semantic)** → `kairo_semantic_classified`
- **Stage 6 (placement)** → `kairo_placement_classified`
- **Stage 7 (backend mapping)** → `kairo_backend_mapped`

Stage 4 (io_uring hint plumbing) does not get a dedicated tracepoint
because the hint source is captured in `kairo_request_classified`.

## Running Stage 8 Experiments

```bash
# Basic run on unpatched kernel (tracepoints_available=false)
./scripts/run_stage8_trace_experiment.sh /mnt/nvme/kairo.test nvme0n1 --trace-mode none

# With ftrace on a patched kernel
./scripts/run_stage8_trace_experiment.sh /mnt/nvme/kairo.test nvme0n1 --trace-mode ftrace

# With bpftrace on a patched kernel
./scripts/run_stage8_trace_experiment.sh /mnt/nvme/kairo.test nvme0n1 --trace-mode bpftrace

# Dry run
./scripts/run_stage8_trace_experiment.sh /mnt/nvme/kairo.test nvme0n1 --dry-run

# Parse results
python3 scripts/parse_stage8_trace_log.py results/stage8/*/trace/kairo_trace.log --pretty
python3 scripts/parse_stage8_trace_log.py results/stage8/*/trace/kairo_trace.log --csv
```

## What Remains Unvalidated

- Whether tracepoint overhead in the decode dispatch hot path is acceptable
  (sub-microsecond target)
- Whether all 9 tracepoints produce useful signal for kernel developers
- Whether the tracepoint payload fields match the metadata actually
  available at each lifecycle stage in a real kernel
- Whether bpftrace scripts correctly parse tracepoint output across
  kernel versions
- Whether the `kairo_merge_decision` and `kairo_semantic_classified`
  tracepoints can be wired before their Stage 3/5 metadata plumbing is
  compile-validated

## Important Notes

- Stage 8 tracepoints are **RFC/POC**.
- Tracepoint payloads are **not stable ABI**.
- Trace scripts require a **patched kernel** with Kairo tracepoints.
- On unpatched kernels, experiment scripts still run and report
  `tracepoints_available=false`.
- Stage 8 does **not** add physical NVMe placement or claim LKML
  readiness.
- Foundation patches remain untouched.
