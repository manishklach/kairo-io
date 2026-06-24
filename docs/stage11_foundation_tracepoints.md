# Stage 11: Compile-Targeted Foundation Tracepoints

Stage 11 adds a small, credible compile-targeted subset of Kairo tracepoints
to the Linux 6.8.x foundation stack.

It does **not** claim LKML readiness.

It does **not** claim tracepoint ABI stability.

It does **not** require root or boot validation.

## Why a Small Compile-Targeted Subset Matters

The existing Stage 8 tracepoint scaffold (patch 0017) defines 9 tracepoints
covering classification, scheduler decisions, dispatch, demotion, merge,
semantic flags, placement metadata, and backend mapping. That scaffold is
broad and RFC-only — useful for architecture exploration but too large for
foundation integration.

Stage 11 takes a different approach:

- **Only four tracepoints** that hook directly into foundation code paths
- **Compile-targeted** — intended to actually compile against Linux 6.8.x
- **Small payloads** — no model/session/backend fields
- **Call-site annotations** — `LINUX-6.8-CHECK` marks where each trace
  call should be placed

This makes the foundation tracepoint set credible as a local validation
tool without overcommitting to a broad tracepoint ABI.

## Difference from Stage 8 (Broad Tracepoint Scaffold)

| Aspect | Stage 8 (0017) | Stage 11 (0022 / foundation 0005) |
|--------|----------------|-----------------------------------|
| Tracepoints | 9 | 4 |
| Classification | `kairo_request_classified` | `kairo_request_classified` |
| Decode dispatch | `kairo_decode_dispatch` | `kairo_decode_dispatch` |
| Prefetch dispatch | `kairo_prefetch_dispatch` | `kairo_prefetch_dispatch` |
| Write demoted | `kairo_write_demoted` | `kairo_write_demoted` |
| Scheduler decision | `kairo_scheduler_decision` | — |
| Merge decision | `kairo_merge_decision` | — |
| Semantic classified | `kairo_semantic_classified` | — |
| Placement classified | `kairo_placement_classified` | — |
| Backend mapped | `kairo_backend_mapped` | — |
| Foundation integration | No | Yes (foundation patch 0005) |
| Compile target | RFC-only | Linux 6.8.x |
| Call-site annotations | CONCEPTUAL-HOOK | LINUX-6.8-CHECK |
| Payload fields | Full (incl. model/session/backend) | Minimal (dev, sector, nr_bytes, io_class, budget) |

## The Four Tracepoints

### `kairo_request_classified`

Emitted when Kairo classifies a request.

**Fields:** `dev`, `sector`, `nr_bytes`, `op`, `ioprio`, `io_class`, `flags`

**Expected call site:** In `block/blk-mq.c` near `kairo_classify_rq()` or
`rq_set_kairo_from_bio()`, after the request has valid sector/bytes/op metadata
and the classified `io_class` is known.

### `kairo_decode_dispatch`

Emitted when a decode-critical read is dispatched from mq-deadline.

**Fields:** `dev`, `sector`, `nr_bytes`, `budget_used`

**Expected call site:** In `dd_kairo_dispatch_decode_request()` in
`block/mq-deadline.c`, after the request is selected for dispatch and
before `dd_kairo_finalize_request()`.

### `kairo_prefetch_dispatch`

Emitted when a prefetch read is dispatched from mq-deadline.

**Fields:** `dev`, `sector`, `nr_bytes`, `budget_used`, `deadline_ns`,
`deadline_near`

**Expected call site:** In `dd_kairo_dispatch_prefetch_request()` in
`block/mq-deadline.c` (foundation patch 0003), after the request is
selected for dispatch.

### `kairo_write_demoted`

Emitted when a prefill or evict write is demoted behind decode/prefetch.

**Fields:** `dev`, `sector`, `nr_bytes`, `io_class`, `reason`,
`starvation_escape`

**Expected call site:** In `dd_kairo_should_demote_prefill()` or
`dd_kairo_should_demote_evict()` in `block/mq-deadline.c`, when the
demotion decision is true.

## How to Apply with `--with-tracepoints`

```bash
# Apply foundation stack only (0001-0004)
./kernel/integration/linux-6.8/apply_foundation_stack.sh /path/to/linux-6.8

# Apply foundation stack + tracepoints (0001-0005)
./kernel/integration/linux-6.8/apply_foundation_stack.sh /path/to/linux-6.8 --with-tracepoints
```

Default behavior (no `--with-tracepoints`) applies only patches 0001-0004.
The tracepoint patch (0005) is only applied when explicitly requested.

## How to Validate Without Boot

```bash
# Validate foundation tracepoint presence in patched tree
./kernel/integration/linux-6.8/validate_foundation_tracepoints.sh /path/to/patched-linux-6.8
```

This checks for:

- `include/trace/events/kairo.h` exists
- `TRACE_SYSTEM kairo` in the header
- All four `TRACE_EVENT(...)` definitions
- All four `trace_kairo_*()` call sites in the source files

Does not require boot, root, or a running kernel.

## How to Run the Experiment

```bash
# Dry-run (no kernel tracepoints, no real runs)
./scripts/run_stage11_foundation_trace_experiment.sh /tmp/kairo.bin loop0 --trace-mode none --skip-counters --dry-run

# With ftrace on a patched kernel with tracepoints available
./scripts/run_stage11_foundation_trace_experiment.sh /tmp/kairo.bin /dev/nvme0n1 --trace-mode ftrace

# Parse results
python3 scripts/parse_stage11_foundation_trace_summary.py results/stage11/<timestamp>/*/summary.log --pretty
```

## What Remains Unvalidated

- Whether `rq->q->sysfs_dev->devt` is available at all trace call sites
  (varies by kernel version)
- Whether `trace_kairo_request_classified()` compiles in `blk-mq.c` without
  circular header dependencies
- Whether `trace_kairo_write_demoted()` call site placement is correct
  inside the demotion helpers
- Whether the tracepoint overhead is acceptable in the hot dispatch path
- End-to-end trace capture on a patched kernel with real NVMe hardware
- Interaction with BPF dispatch hook (patch 0016)
