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

## Stage 8

- Broad RFC/POC patches involved: benchmark, `tools/bpf`, validation scripts
- What should compile:
  - benchmark modes
  - runtime validation scripts
  - tracing helpers
- What should be measurable:
  - A/B decode latency
  - multisession interference
  - counter deltas and block-latency traces
- What is still RFC-only:
  - end-to-end proof for the full nine-patch series
