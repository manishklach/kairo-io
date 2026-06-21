# Kairo Roadmap

## Phase 1: Decode Priority Validation

- validate `0001` on concrete Linux 6.8.x source trees
- boot a patched kernel
- confirm sysfs counters are visible
- prove non-zero `kairo_decode_dispatches_delta` during mixed benchmark runs

## Phase 2: Classification and Hint Plumbing

- refine `0002` so scheduler code uses shared request classification helpers
- validate whether the `0003` experimental hint path should remain `ioprio`-backed or shift toward `io_uring`
- confirm benchmark modes can drive decode, prefetch, prefill, and eviction separately

## Phase 3: Merge and Prefetch Policy

- evaluate whether `0004` changes request shape under large-block KV-cache reads
- validate `0005` deadline handling under mixed decode and prefetch pressure
- compare p95 and p99 decode latency against baseline

## Phase 4: Semantics and Placement

- assess whether `0006` ephemeral semantics reduce collateral cache pollution
- trial `0007` software-only placement grouping
- inspect how much backend value `0008` adds on feature-capable drives

## Phase 5: Observability and Iteration

- extend `0009` counters only where they materially explain benchmark behavior
- keep the benchmark and scripts aligned with whatever Kairo paths are truly active
- update [tested_kernel_matrix.md](tested_kernel_matrix.md) as each tree moves from apply/build to boot/runtime validation
