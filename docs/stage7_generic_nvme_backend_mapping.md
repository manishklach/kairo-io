# Stage 7: Generic NVMe Backend Mapping Hooks

## Objective

Add a generic RFC/POC backend-mapping layer that converts Kairo placement
metadata (model/session/cache-pool/placement-group/lifetime) into neutral
backend placement classes with optional NVMe feature-detected mapping
scaffolding.

This is the bridge between Stage 6's placement/lifetime metadata and
future NVMe backend support. It does **not** claim physical data placement.

## Status

- RFC/POC scaffold, benchmark-visible, no hardware placement yet.
- No stable UAPI proposed.
- No LKML submission planned at this stage.

## Key Concept: Backend Class

Stage 7 introduces a neutral internal `enum kairo_backend_class` that
abstracts placement intent:

| Class | Meaning | Derived From |
|-------|---------|-------------|
| `KAIRO_BACKEND_NONE` | No placement metadata | `lifetime_class == KAIRO_LIFE_NONE` |
| `KAIRO_BACKEND_SHORT_LIVED` | Short-lived cache data | `KAIRO_LIFE_SHORT` |
| `KAIRO_BACKEND_SESSION_LOCAL` | Session-local data | `KAIRO_LIFE_SESSION` |
| `KAIRO_BACKEND_MODEL_LOCAL` | Model-local data | `KAIRO_LIFE_MODEL` |
| `KAIRO_BACKEND_RECOMPUTABLE` | Recomputable data | `recompute_ok == true` (if no stronger lifetime) |
| `KAIRO_BACKEND_PERSISTENT` | Persistent durable data | `KAIRO_LIFE_PERSISTENT` |

## Backend Hint Structure

```c
struct kairo_backend_hint {
    enum kairo_backend_class backend_class;
    u32 stream_id;           // populated if NVMe Streams capable
    u32 fdp_placement_id;    // populated if NVMe FDP capable
    u32 zone_hint;           // populated if NVMe ZNS capable
    u32 placement_group;
    u32 cache_pool_id;
    u32 flags;
};
```

Flags:

| Flag | Meaning |
|------|---------|
| `KAIRO_BACKEND_F_STREAMS_CAPABLE` | Device supports NVMe Streams |
| `KAIRO_BACKEND_F_FDP_CAPABLE` | Device supports NVMe FDP |
| `KAIRO_BACKEND_F_ZNS_CAPABLE` | Device supports NVMe ZNS |
| `KAIRO_BACKEND_F_NOOP_FALLBACK` | No backend support detected; no-op |
| `KAIRO_BACKEND_F_RECOMPUTABLE` | Request marked recomputable |

## Mapping Rules

```
Stage 6 metadata                    ->  Stage 7 backend class
--------------------------------------------------------------
KAIRO_LIFE_SHORT                       KAIRO_BACKEND_SHORT_LIVED
KAIRO_LIFE_SESSION                     KAIRO_BACKEND_SESSION_LOCAL
KAIRO_LIFE_MODEL                       KAIRO_BACKEND_MODEL_LOCAL
KAIRO_LIFE_PERSISTENT                  KAIRO_BACKEND_PERSISTENT
recompute_ok (no lifetime)             KAIRO_BACKEND_RECOMPUTABLE
recompute_ok + any lifetime            KAIRO_BACKEND_F_RECOMPUTABLE flag
cache_pool_id                          placement pool selector
placement_group                        placement group selector
```

## NVMe Feature Detection (Scaffold)

These functions detect backend support. Currently all return `false` until
real detection is wired:

- `nvme_kairo_streams_supported(q)` — NVMe Streams support
- `nvme_kairo_fdp_supported(q)` — NVMe FDP (Flexible Data Placement) support
- `nvme_kairo_zns_supported(q)` — NVMe ZNS (Zoned Namespace) support

When detected, the mapping follows this pseudo-policy:

```
If Streams supported:
    placement_group / cache_pool_id -> stream_id

If FDP supported:
    cache_pool_id / placement_group -> fdp_placement_id

If ZNS supported:
    backend_class -> zone_hint

If none supported:
    KAIRO_BACKEND_F_NOOP_FALLBACK set
```

## NVMe Hook Points

The patch adds these scaffold functions:

```c
// Prepare backend hint from request metadata
static void nvme_kairo_prepare_backend_hint(struct request *rq,
    struct kairo_backend_hint *hint);

// Apply backend hint to NVMe command (RFC/POC: no-op)
static void nvme_kairo_apply_backend_hint(struct request *rq,
    struct kairo_backend_hint *hint);

// Legacy simpler mapping (retained for backward compatibility)
static void nvme_kairo_select_mapping(struct request *rq,
    struct nvme_kairo_mapping *map);
```

The `apply_backend_hint` function is currently a no-op. When support is
wired, it would set NVMe command fields such as stream ID, FDP placement
handle, or ZNS append hint.

## Stage 7 Counters (sysfs via 0009)

| Counter | Type | Description |
|---------|------|-------------|
| `kairo_backend_mapping_attempts` | u64 | Total backend mapping attempts |
| `kairo_backend_noop_fallbacks` | u64 | Requests with no active backend (no-op fallback) |
| `kairo_backend_stream_hints` | u64 | Requests mapped to NVMe Stream hint |
| `kairo_backend_fdp_hints` | u64 | Requests mapped to NVMe FDP hint |
| `kairo_backend_zns_hints` | u64 | Requests mapped to NVMe ZNS hint |
| `kairo_backend_short_lived` | u64 | Requests classified as short-lived |
| `kairo_backend_session_local` | u64 | Requests classified as session-local |
| `kairo_backend_model_local` | u64 | Requests classified as model-local |
| `kairo_backend_recomputable` | u64 | Requests classified as recomputable |
| `kairo_backend_persistent` | u64 | Requests classified as persistent |

## Benchmark Backend Modes

The benchmark supports `--backend-mode` to model mapping behavior:

| Mode | Behavior |
|------|----------|
| `none` (default) | No backend placement modeling |
| `generic` | Print backend class based on lifetime metadata |
| `streams` | Model stream-style mapping (stream_id = placement_group or cache_pool) |
| `fdp` | Model FDP placement-id mapping |
| `zns` | Model zone-style lifetime mapping |

Benchmark output fields for backend mode:

```
backend_mode=generic
backend_class=KAIRO_BACKEND_SHORT_LIVED
stream_id=2
fdp_placement_id=0
zone_hint=0
backend_noop_fallback=false
```

The benchmark does not issue real NVMe placement directives.

## Experiment Script

```
scripts/run_stage7_backend_mapping_experiment.sh
```

Usage:

```bash
./scripts/run_stage7_backend_mapping_experiment.sh <file-path> <block-device> [options]
```

Canonical cases:

1. **generic-short-lived** — generic mode, short lifetime
2. **generic-session-local** — generic mode, session lifetime, multisession
3. **streams-model-local** — stream mode, model lifetime, 4 pools/8 groups
4. **fdp-cache-pool** — FDP mode, model lifetime, 4 pools/4 groups
5. **zns-short-lived** — ZNS mode, ephemeral-recomputable, eviction pressure

Results layout: `results/stage7/<timestamp>/` with the same structure as
Stage 6.5 (run_metadata.log, per-case command.txt/bench.log/summary.log,
counters-before/after, root summary.csv).

## Parser

```
scripts/parse_stage7_backend_summary.py
```

Usage:

```bash
python3 scripts/parse_stage7_backend_summary.py results/stage7/*/summary.log --csv
python3 scripts/parse_stage7_backend_summary.py results/stage7/*/summary.log --pretty
```

## Stage 7.5: Hook Audit and Mapping Hardening

Stage 7.5 ([audit document](stage7_5_nvme_hook_audit.md)) performed:

- Hook-point analysis: each 0008 hook classified as compile-target
  or conceptual with explicit compile-risk annotations
- `struct kairo_backend_caps` abstraction replacing per-feature
  `_supported()` helpers
- `kairo_backend_hint_apply_caps()` helper for unified caps-to-hint
  mapping
- 0008 reorganized into sections A–H with annotation comments at
  each hook point
- Benchmark refactor: `kairo_compute_backend_model()` consolidation
- Python validator (`scripts/validate_stage7_backend_mapping.py`)
  integrated into `scripts/validate_patch_stack.sh`

## What Remains Unvalidated

- Whether the generic `kairo_backend_class` abstraction maps usefully to
  real NVMe Streams/FDP/ZNS device capabilities
- Whether the `nvme_kairo_prepare_backend_hint` / `apply_backend_hint`
  split is the right API boundary
- Whether backend detection via `nvme_kairo_streams_supported()` etc.
  needs device-specific identify commands or can use generic feature bits
- Whether the benchmark backend modeling (streams/fdp/zns) matches
  real device behavior
- Whether physical placement through these hooks provides measurable
  improvement over software-only grouping (Stage 6)

## Important Notes

- Stage 7 does **not** claim physical data placement.
- Stage 7 creates a generic mapping scaffold that can later be connected
  to feature-detected NVMe backends.
- All NVMe hooks are safe no-op unless backend support is detected and
  wired in a future stage.
- The benchmark models mapping behavior in user space; it does not send
  real NVMe placement directives to hardware.
