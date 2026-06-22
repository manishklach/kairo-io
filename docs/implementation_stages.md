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

## Stage 7

- Broad RFC/POC patches involved: `0008`
- What should compile:
  - feature-detected NVMe mapping hooks
- What should be measurable:
  - backend differentiation on hardware that exposes useful generic features
- What is still RFC-only:
  - effectiveness of Streams/FDP/ZNS mapping on target devices

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
