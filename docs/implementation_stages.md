# Implementation Stages

Kairo uses two patch tracks:

- Broad RFC/POC architecture patches: concept coverage across the full
  nine-patch series.
- Foundation patches: the smaller compile-targeted kernel core under
  `kernel/patches/foundation/`.

The foundation stack currently covers Stage 1 and Stage 2 only.

## Stage 1

- Broad RFC/POC patches involved: `0002`, `0001`, `0009`
- Foundation patches involved: `foundation/0001`, `foundation/0002`, `foundation/0004`
- What should compile:
  - local request classification helpers
  - `mq-deadline` decode-priority path
  - aligned Kairo sysfs counters
- What should be measurable:
  - `decode_avg_us`
  - `decode_p95_us`
  - `decode_p99_us`
  - `kairo_decode_dispatches`
  - `kairo_normal_dispatches`
- What is still RFC-only:
  - broader hint plumbing beyond `ioprio`
  - anything outside the foundation stack

## Stage 2

- Broad RFC/POC patches involved: `0005`
- Foundation patches involved: `foundation/0003`, `foundation/0004`
- What should compile:
  - prefetch metadata fields and scheduler recognition hooks
- What should be measurable:
  - prefetch pressure runs versus decode tail latency
- What is still RFC-only:
  - tuned deadline policy and starvation tradeoff validation

## Stage 3

- Broad RFC/POC patches involved: `0004`, `0009`, `0002`
- What should compile:
  - Kairo merge-bias helpers (`kairo_should_bias_merge`, `kairo_merge_within_limits`)
  - per-request merge-instrumentation flags set in `attempt_merge` and `blk_mq_bio_merge`
  - request-size histogram counters consumed at dispatch time
- What should be measurable:
  - `kairo_merge_attempts` / `kairo_merge_successes` / `kairo_merge_rejects`
  - `kairo_decode_merge_attempts` / `kairo_decode_merge_successes`
  - `kairo_prefetch_merge_attempts` / `kairo_prefetch_merge_successes`
  - `kairo_small_decode_reads` / `kairo_large_decode_reads` (threshold via `kairo_large_read_kb`)
  - full request-size histogram: `kairo_{decode,prefetch}_read_{4k,16k,64k,256k,1m,4m,gt4m}`
  - benchmark access patterns: random, sequential, strided, clustered
  - benchmark modes: merge-friendly (sequential, large block), merge-hostile (fragmented, random/session-interleaved)
- What is still RFC-only:
  - full validation of merge policy on real devices
  - whether the histogram counters are better served by debugfs snapshots instead of sysfs

## Stage 4

- Broad RFC/POC patches involved: `0003`
- What should compile:
  - experimental `RWF_KAIRO_*` and `kiocb` plumbing
  - conceptual `kiocb` -> `bio` -> `request` Kairo metadata helpers
- What should be measurable:
  - benchmark `--hint-mode ioprio|rwf|both`
  - `rwf_*_{attempts,fail}` counters in the benchmark summary
  - staged hint-source counters such as `kairo_ioprio_hinted_requests`
- What is still RFC-only:
  - scaffolded / local RFC, not compile-validated
  - final local interface choice for hint propagation

## Stage 5

- Broad RFC/POC patches involved: `0006`
- What should compile:
  - ephemeral and recomputable flag scaffolding
  - local semantic flag helpers on `kiocb`, `bio`, and `request` metadata
- What should be measurable:
  - benchmark `--semantic-mode normal|ephemeral|recomputable|ephemeral-recomputable`
  - `rwf_ephemeral_*`, `rwf_recompute_*`, `rwf_no_durability_*`, `rwf_avoid_pagecache_*`
  - semantic counter deltas such as `kairo_ephemeral_requests`
- What is still RFC-only:
  - scaffolded / local RFC, not compile-validated
  - exact durability and cache-management semantics

## Stage 6

- Broad RFC/POC patches involved: `0007`, `0009`
- Userspace header: `include/kairo_hints.h` (placement structs and flags)
- Benchmark: `kairo_bench.c` (placement CLI options and output fields)
- Scripts: `scripts/run_stage6_placement_experiment.sh`,
          `scripts/parse_stage6_placement_summary.py`
- What should compile:
  - `enum kairo_lifetime_class`, `struct kairo_placement_hint`, helpers,
    synthetic default init (`blk_mq_kairo_default_placement`)
  - scaffold placement/lifetime counters in `mq-deadline.c`
- What should be measurable:
  - software-only grouping experiments by model/session/cache pool
  - benchmark `--lifetime`, `--recompute-ok`, `--cache-pool-id`,
    `--placement-group`, `--cache-pools`, `--placement-groups`
  - sysfs scaffold counters: `kairo_placement_hints`,
    `kairo_lifetime_*_count`, `kairo_has_*_count`
- What is still RFC-only:
  - stable mapping semantics through the stack
  - NVMe Streams/FDP/ZNS mapping (deferred to Stage 7)
  - scheduler policy changes based on lifetime class

## Stage 6.5

- Status: benchmark/experiment harness, not foundation-integrated
- Scripts involved:
  - `scripts/run_stage6_placement_experiment.sh` — hardened harness accepting
    `<file-path> <block-device>` with structured `results/stage6/<timestamp>/` output
  - `scripts/parse_stage6_placement_summary.py` — CSV and pretty-printed summary
    parser supporting counter delta columns
  - `scripts/collect_kairo_counters.sh` — Stage 6 counter coverage (both naming sets)
- What is measurable:
  - five canonical placement/lifetime cases with before/after counter deltas
  - structured run metadata and per-case `summary.log` files
  - aggregated `summary.csv` across all cases
- What is still RFC-only:
  - NVMe/FDP/ZNS mapping (deferred to Stage 7)
  - physical placement control based on placement-group hints

## Stage 7

- Broad RFC/POC patches involved: `0008`, `0009`
- Userspace header: `include/kairo_hints.h` (`enum kairo_backend_mode`)
- Benchmark: `kairo_bench.c` (`--backend-mode` option, mapping output fields)
- Scripts: `scripts/run_stage7_backend_mapping_experiment.sh`,
          `scripts/parse_stage7_backend_summary.py`
- Docs: `docs/stage7_generic_nvme_backend_mapping.md`
- What should compile:
  - `enum kairo_backend_class`, `struct kairo_backend_hint`, helpers
  - feature-detected NVMe mapping hooks (no-op fallback when absent)
  - backend mapping scaffold counters in `mq-deadline.c`
- What should be measurable:
  - backend class mapping from Stage 6 lifetime metadata
  - benchmark `--backend-mode none|generic|streams|fdp|zns`
  - sysfs scaffold counters: `kairo_backend_mapping_attempts`,
    `kairo_backend_*_hints`, `kairo_backend_*_lived`/`_local`/`_persistent`
  - benchmark output fields: `backend_mode`, `backend_class`, `stream_id`,
    `fdp_placement_id`, `zone_hint`, `backend_noop_fallback`
- What is still RFC-only:
  - real NVMe hardware placement (Streams, FDP, ZNS)
  - physical backend mapping effectiveness on target devices
  - detection of NVMe feature bits via identify commands
  - application of backend hints to NVMe commands

## Stage 7.5

- Broad RFC/POC patches involved: `0008` (rewritten sections A-H)
- Audit doc: `docs/stage7_5_nvme_hook_audit.md`
- Audit script: `kernel/integration/linux-6.8/audit_nvme_hooks.sh`
- Validator: `scripts/validate_stage7_backend_mapping.py`
- What changed:
  - 0008 reorganized into sections A–H with `struct kairo_backend_caps` abstraction
  - Per-feature `nvme_kairo_streams_supported()` / `_fdp_` / `_zns_` replaced by unified `nvme_kairo_get_backend_caps()`
  - Added `kairo_backend_hint_apply_caps()` helper
  - `backend` hint stored inline in `struct kairo_backend_hint` inside `kairo_hints.placement`
  - Compile-risk annotations added per hook point (COMPILE-TARGET, CONCEPTUAL-HOOK, VERSION-SENSITIVE)
  - Benchmark refactored: `kairo_compute_backend_model()` replaces 5 individual helpers
  - `validate_patch_stack.sh` integrated with Python validator
- What should be validated:
  - All sections A–H present in 0008
  - Compile-risk annotations match audit document classifications
  - Python validator passes against current 0008, docs, and benchmark
  - Audit script detects candidate symbols in real Linux 6.8 tree
  - Benchmark compiles with refactored backend model computation
- What is still RFC-only:
  - Real NVMe hardware placement (Streams, FDP, ZNS)
  - Wiring of caps detection to real identify-command data
  - Physical backend mapping effectiveness on target devices

## Supernova Patches (0010–0016)

Seven patches in dependency order that harden the Kairo proof of concept
from instrumentation-grade to a structurally sound I/O scheduling
framework:

| Patch | Area | Status | KV perf impact |
|-------|------|--------|----------------|
| `0010` | real classification | implemented | root dependency — without it, 0001 measures noise |
| `0011` | write anti-starvation | implemented | correctness gate; benchmarks invalid without it |
| `0012` | tag reservation | implemented | highest single-patch latency impact |
| `0013` | O(1) dispatch FIFO | implemented | eliminates latency cliff under contention |
| `0014` | io_uring SQE hint | implemented | enables production-realistic classification |
| `0015` | real merge bias | implemented | reduces NVMe command count per decode step |
| `0016` | BPF dispatch hook | implemented | architectural differentiator: programmable I/O scheduling |

## Stage 8 (Tracepoints)

- Broad RFC/POC patches involved: `0017`
- Userspace header: `include/trace/events/kairo.h` (new)
- What should compile:
  - tracepoint header `include/trace/events/kairo.h` (TRACE_EVENT definitions)
  - tracepoint call sites in `block/blk-mq.c`, `block/mq-deadline.c`,
    `block/blk-merge.c`, `drivers/nvme/host/core.c`
  - runtime validation scripts
  - bpftrace scripts
- What should be measurable:
  - per-request lifecycle tracepoints (classification, scheduler decision,
    dispatch, demotion, merge, semantic, placement, backend mapping)
  - structured trace logs in `results/stage8/<timestamp>/`
  - trace log parsing with CSV and pretty-printed summary
  - A/B decode latency with tracepoint confirmation
- What is still RFC-only:
  - all tracepoints (not stable ABI)
  - bpftrace script compatibility across kernel versions
  - end-to-end proof for the full ten-patch series

## Stage 9

- Status: tooling/validation layer
- Scripts involved:
  - `scripts/check_wsl_environment.sh`
  - `scripts/run_wsl_validation_snapshot.sh`
  - `scripts/parse_validation_snapshot.py`
- What should validate:
  - WSL-friendly repo validation
  - benchmark build
  - dry-run experiment validation
  - smoke benchmark execution
  - generated validation snapshot evidence packaging
- What is still RFC-only:
  - custom kernel boot validation
  - patched-kernel runtime counters
  - physical NVMe placement claims

## Stage 10

- Broad RFC/POC patches involved: `0018`
- Docs: `docs/stage10_adaptive_latency_controller.md`
- Scripts:
  - `scripts/run_stage10_latency_controller_experiment.sh`
  - `scripts/parse_stage10_latency_controller_summary.py`
- What should compile:
  - `enum kairo_controller_mode` and `struct kairo_latency_controller`
    in `mq-deadline.c`
  - controller state init, sample accumulation, p95/p99 computation,
    budget adjustment logic
  - sysfs knobs for controller enable, mode, target p99, control window
  - sysfs counters for controller updates, boost/relax/throttle/release events
  - integration call site in `dd_dispatch_request()`
  - decode pressure signal in demotion helpers
- What should be measurable:
  - controller counters in sysfs when controller is enabled
  - `kairo_adaptive_decode_budget` and `kairo_adaptive_prefetch_budget`
    reflect controller decisions after a window of decode pressure
  - six canonical experiment cases comparing static vs controller-driven scheduling
  - structured output under `results/stage10/<timestamp>/`
  - parseable summary logs with CSV and pretty-printed tables
- What is still RFC-only:
  - real decode latency measurement from inside the kernel (completion hook)
  - controller behavior on real NVMe hardware under true inference patterns
  - precise p95/p99 latency histogram (uses avg/max heuristic)
  - timer-based controller update (currently called from dispatch path)
  - `kairo_controller_update` tracepoint (documented but not wired)
  - interaction with BPF dispatch hook (patch 0016)
  - per-device budget tracking (currently updates global variables)

## Stage 11

- Foundation patches involved: `foundation/0005`
- Broad RFC/POC patches involved: `0022`
- Docs: `docs/stage11_foundation_tracepoints.md`
- Scripts:
  - `kernel/integration/linux-6.8/validate_foundation_tracepoints.sh`
  - `scripts/run_stage11_foundation_trace_experiment.sh`
  - `scripts/parse_stage11_foundation_trace_summary.py`
- Integration: `apply_foundation_stack.sh --with-tracepoints` (optional)
- What should compile:
  - `include/trace/events/kairo.h` with 4 TRACE_EVENT definitions:
    `kairo_request_classified`, `kairo_decode_dispatch`,
    `kairo_prefetch_dispatch`, `kairo_write_demoted`
  - `#include <trace/events/kairo.h>` in `block/blk-mq.c` and
    `block/mq-deadline.c`
  - compile-targeted call site annotations (`LINUX-6.8-CHECK`)
  - trace call in `dd_kairo_dispatch_decode_request()`
  - no model/session/backend fields in tracepoint payloads
- What should be measurable:
  - tracepoint presence in `/sys/kernel/tracing/events/kairo/`
  - per-request lifecycle trace events (classification, dispatch, demotion)
  - experiment harness detects `tracepoints_available=true|false`
  - structured results under `results/stage11/<timestamp>/`
- What distinguishes Stage 11 from Stage 8:
  - Stage 11: 4 tracepoints, compile-targeted foundation, minimal payloads
  - Stage 8: 9 tracepoints, broad RFC scaffold, model/session/backend fields
  - Stage 11 applies only with `--with-tracepoints` flag
  - Stage 11 uses `LINUX-6.8-CHECK` annotations (vs CONCEPTUAL-HOOK in Stage 8)
