# Stage 5: Ephemeral And Recomputable Semantics

Kairo Stage 5 explores a local RFC/POC idea: AI KV-cache storage is not always
ordinary durable file data.

Some KV-cache contents are:

- ephemeral
- session-scoped
- short-lived
- safe to discard after session end
- recomputable from prompt or model state
- poor candidates for page-cache pollution

## Safety Boundary

Stage 5 is explicitly careful about durability semantics.

- Kairo may express `NO_STRONG_DURABILITY` intent for recomputable cache data
- Kairo does not claim the kernel may ignore explicit `fsync()`, `fdatasync()`, `sync()`, or equivalent requests
- the local RFC/POC only models intent signals and possible optimization hooks

## Local Semantic Flags

Stage 5 models these local semantic signals:

- `KAIRO_EPHEMERAL`
- `KAIRO_RECOMPUTABLE`
- `KAIRO_NO_STRONG_DURABILITY`
- `KAIRO_AVOID_PAGECACHE`
- `KAIRO_EVICT_CLEANUP`

These are local experiment semantics, not stable Linux UAPI.

## Flow Through Stage 4 Hints

The intended metadata path is:

```text
userspace benchmark
  -> RWF_KAIRO_EPHEMERAL / RWF_KAIRO_RECOMPUTE / ...
  -> IOCB_KAIRO_EPHEMERAL / IOCB_KAIRO_NO_DURABILITY / ...
  -> bio->kairo_hints.flags
  -> rq->kairo_hints.flags
  -> block-layer classification and accounting
```

## What `avoid-pagecache` Means

`AVOID_PAGECACHE` is an intent signal first.

- it means transient KV-cache traffic should prefer direct or low-cache-pollution paths where the stack supports it
- it does not mean a random kernel layer should forcibly bypass page cache without respecting the actual I/O path
- the RFC/POC uses comments and metadata to show where that policy would be interpreted

## How Eviction Cleanup Is Modeled

Stage 5 treats eviction cleanup as a distinct semantic signal:

- eviction threads model cleanup of short-lived cache contents
- `KAIRO_EVICT_CLEANUP` is intended to mark punch-hole or discard-like cleanup work
- Kairo keeps this separate from ordinary writes so cleanup traffic can be observed independently

## Counters That Prove The Path

Stage 5 adds scaffold counters for:

- `kairo_ephemeral_requests`
- `kairo_recomputable_requests`
- `kairo_no_durability_requests`
- `kairo_avoid_pagecache_requests`
- `kairo_evict_cleanup_requests`

Together with Stage 4 hint-source counters, these show whether requests were
classified with explicit semantic intent or only through fallback behavior.

## Benchmark Modes

The benchmark adds:

- `--semantic-mode normal`
- `--semantic-mode ephemeral`
- `--semantic-mode recomputable`
- `--semantic-mode ephemeral-recomputable`

These run on top of existing `--hint-mode ioprio|rwf|both`.

## How To Run

Build the benchmark locally:

```bash
gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c
```

Run the Stage 5 experiment:

```bash
./scripts/run_stage5_ephemeral_experiment.sh <file-path> <block-device>
```

This runs:

1. normal semantics
2. ephemeral
3. recomputable
4. ephemeral-recomputable

Results are saved under `results/stage5/`.
