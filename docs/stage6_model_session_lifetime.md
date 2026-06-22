# Stage 6: Model/Session/Lifetime Placement Metadata

## Objective

Add model/session/cache-pool/placement-group/lifetime metadata as an RFC/POC
scaffold layer to the Kairo request-hint path. This is a broad exploration
patch (0007) plus scaffold counters (0009); it does not propose stable UAPI
or NVMe/FDP/ZNS mapping.

## Motivation

AI KV-cache workloads generate I/O with known scoping properties:
- A single inference request reads/writes at most a few model layers
- Cache entries belong to a specific model and session
- Cache data is often short-lived (session-local or recomputable)
- Cache writes from different sessions should ideally land in separate
  placement groups to avoid interference

By plumbing model/session/lifetime hints, we enable:
- Software-only grouping experiments without hardware changes
- Future generic placement-group mapping (Streams, FDP, ZNS)
- Scheduler-aware partitioning of short-lived vs persistent data

## Patches Involved

| Patch | File | Purpose |
|-------|------|---------|
| 0007 | `include/linux/blk_types.h`, `block/blk-mq.c` | Placement/lifetime struct, helpers, synthetic default init |
| 0009 | `block/mq-deadline.c` | Scaffold counters: `kairo_placement_hints`, `kairo_lifetime_*_count`, `kairo_has_*_count` |

## Data Structures (kernel side)

```c
enum kairo_lifetime_class {
    KAIRO_LIFE_NONE = 0,
    KAIRO_LIFE_SHORT,
    KAIRO_LIFE_SESSION,
    KAIRO_LIFE_MODEL,
    KAIRO_LIFE_PERSISTENT,
};

struct kairo_placement_hint {
    u32 model_id;
    u32 session_id;
    u32 cache_pool_id;
    u32 placement_group;
    enum kairo_lifetime_class lifetime_class;
    bool recompute_ok;
};
```

## Helper Functions (added by 0007)

| Function | Purpose |
|----------|---------|
| `kairo_has_model_id(rq)` | Returns true if `model_id != 0` |
| `kairo_has_session_id(rq)` | Returns true if `session_id != 0` |
| `kairo_has_cache_pool(rq)` | Returns true if `cache_pool_id != 0` |
| `kairo_is_short_lived(rq)` | True if `lifetime_class == KAIRO_LIFE_SHORT` |
| `kairo_is_session_lived(rq)` | True if `lifetime_class == KAIRO_LIFE_SESSION` |
| `kairo_is_model_lived(rq)` | True if `lifetime_class == KAIRO_LIFE_MODEL` |
| `kairo_is_persistent_lived(rq)` | True if `lifetime_class == KAIRO_LIFE_PERSISTENT` |
| `kairo_recompute_ok(rq)` | Returns the `recompute_ok` flag |

## Synthetic Defaults

In `blk_mq_rq_ctx_init`, after existing Kairo initializers, a new call to
`blk_mq_kairo_default_placement(rq)` sets:
- `lifetime_class` → `KAIRO_LIFE_NONE`
- `recompute_ok` → `false`
- All IDs (`model_id`, `session_id`, `cache_pool_id`, `placement_group`) → 0

These defaults ensure no behavioral change for unlabeled I/O.

## User-Space API (include/kairo_hints.h)

New types and helpers in the local benchmark header:

```c
enum kairo_lifetime_class_user {
    KAIRO_USER_LIFE_NONE = 0,
    KAIRO_USER_LIFE_SHORT,
    KAIRO_USER_LIFE_SESSION,
    KAIRO_USER_LIFE_MODEL,
    KAIRO_USER_LIFE_PERSISTENT,
};

struct kairo_user_placement_hint {
    uint32_t model_id;
    uint32_t session_id;
    uint32_t cache_pool_id;
    uint32_t placement_group;
    uint32_t lifetime_class;
    uint32_t flags;
};
```

Placement hint flags:
- `KAIRO_USER_HINT_HAS_MODEL_ID` (1U << 0)
- `KAIRO_USER_HINT_HAS_SESSION_ID` (1U << 1)
- `KAIRO_USER_HINT_HAS_CACHE_POOL` (1U << 2)
- `KAIRO_USER_HINT_RECOMPUTE_OK` (1U << 3)
- `KAIRO_USER_HINT_PLACEMENT_GROUP` (1U << 4)

## Benchmark Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--model-id N` | int | 0 | Fixed model_id for all workers (0 = per-worker distribution) |
| `--session-id N` | int | 0 | Fixed session_id for all workers |
| `--cache-pool-id N` | int | 0 | Fixed cache_pool_id for all workers |
| `--placement-group N` | int | 0 | Fixed placement_group for all workers |
| `--lifetime NAME` | str | none | `short`, `session`, `model`, or `persistent` |
| `--recompute-ok` | flag | off | Mark I/O as recomputable |
| `--cache-pools N` | int | 1 | Number of cache pools for distribution |
| `--placement-groups N` | int | 1 | Number of placement groups for distribution |

## Scaffold Counters (sysfs via 0009)

| Counter | Type | Description |
|---------|------|-------------|
| `kairo_placement_hints` | u64 | Total requests with non-zero placement metadata |
| `kairo_lifetime_short_count` | u64 | Requests with `KAIRO_LIFE_SHORT` |
| `kairo_lifetime_session_count` | u64 | Requests with `KAIRO_LIFE_SESSION` |
| `kairo_lifetime_model_count` | u64 | Requests with `KAIRO_LIFE_MODEL` |
| `kairo_lifetime_persistent_count` | u64 | Requests with `KAIRO_LIFE_PERSISTENT` |
| `kairo_recompute_ok_count` | u64 | Requests with `recompute_ok == true` |
| `kairo_has_model_id_count` | u64 | Requests with non-zero `model_id` |
| `kairo_has_session_id_count` | u64 | Requests with non-zero `session_id` |
| `kairo_has_cache_pool_count` | u64 | Requests with non-zero `cache_pool_id` |

## Experiment Script

Use `scripts/run_stage6_placement_experiment.sh` to exercise all new CLI options.

It runs the following scenarios:

1. **Baseline** — no placement metadata
2. **Fixed model-id** — all workers share `model_id=1`
3. **Fixed session-id** — all workers share `session_id=42`
4. **Fixed cache-pool+placement** — single pool/group for all
5. **Lifetime classes** — one run per lifetime class
6. **Recompute-ok flag** — marks writes as recomputable
7. **Multiple pools/groups** — `--cache-pools 4 --placement-groups 2`
8. **Combined** — metadata fields simultaneously
9. **Multisession mode** — multisession + 4 cache pools + session lifetime

## Parser Utility

Use `scripts/parse_stage6_placement_summary.py` to convert benchmark output
into a formatted comparison table.

Usage:
```bash
./scripts/run_stage6_placement_experiment.sh 2>&1 | tee stage6_results.log
python3 scripts/parse_stage6_placement_summary.py stage6_results.log
```

## What Still Needs Validation

- Whether the `kairo_placement_hint` struct inside `struct request` is
  within acceptable size limits for the hot allocator
- Whether `blk_mq_kairo_default_placement` adds measurable hot-path overhead
- Whether software-only grouping (by model_id/session_id) provides any
  measurable latency improvement before NVMe Streams/FDP mapping
- Whether `KAIRO_LIFE_SHORT` / `KAIRO_LIFE_SESSION` should influence
  scheduler demotion priority (separate from `KAIRO_IO_EVICT`)
- Whether the user-space placement struct (`kairo_user_placement_hint`)
  should carry additional fields (e.g., device-local stream-id hint)

## Related Documents

- `docs/implementation_stages.md` — Stage 6 overview
- `docs/full_architecture_status.md` — architecture status table
- `docs/patch_series.md` — series-level concept descriptions
