# Implementation Stages

## Stage 1

- Patches involved: `0002`, `0001`, `0009`
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
  - `kairo_hinted_requests`
- What is still RFC-only:
  - broader hint plumbing beyond `ioprio`
  - anything outside the foundation stack

## Stage 2

- Patches involved: `0005`
- What should compile:
  - prefetch metadata fields and scheduler recognition hooks
- What should be measurable:
  - prefetch pressure runs versus decode tail latency
- What is still RFC-only:
  - tuned deadline policy and starvation tradeoff validation

## Stage 3

- Patches involved: `0004`
- What should compile:
  - merge-bias helper hooks and instrumentation points
- What should be measurable:
  - request-shape changes
  - merge-attempt and merge-success counters once wired
- What is still RFC-only:
  - full validation of merge policy on real devices

## Stage 4

- Patches involved: `0003`
- What should compile:
  - experimental `RWF_KAIRO_*` and `kiocb` plumbing
- What should be measurable:
  - user-space hint path readiness versus current `ioprio` fallback
- What is still RFC-only:
  - final local interface choice for hint propagation

## Stage 5

- Patches involved: `0006`
- What should compile:
  - ephemeral and recomputable flag scaffolding
- What should be measurable:
  - qualitative page-cache and cleanup behavior during local experiments
- What is still RFC-only:
  - exact durability and cache-management semantics

## Stage 6

- Patches involved: `0007`
- What should compile:
  - placement and lifetime metadata carriage
- What should be measurable:
  - software-only grouping experiments by model/session/cache pool
- What is still RFC-only:
  - stable mapping semantics through the stack

## Stage 7

- Patches involved: `0008`
- What should compile:
  - feature-detected NVMe mapping hooks
- What should be measurable:
  - backend differentiation on hardware that exposes useful generic features
- What is still RFC-only:
  - effectiveness of Streams/FDP/ZNS mapping on target devices

## Stage 8

- Patches involved: benchmark, `tools/bpf`, validation scripts
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
