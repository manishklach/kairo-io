# Stage 19: KV Residency Heatmap

**Stage 19** adds a conceptual KV-cache residency heatmap that tracks
per-region access frequency, recency, and classification (hot, warm,
cold, evictable, protected).  This makes Kairo aware of which cache
regions are actively serving decode traffic vs. sitting idle.

## Why AI KV-Cache Residency Needs Heat Tracking

Traditional storage heatmaps track block-level access frequency for
tiering (e.g., moving hot blocks to SSDs, cold blocks to HDDs).  For
KV-cache workloads, the semantics are different:

- **Decode-hot** regions are read on every inference token generation.
  Evicting them causes decode latency spikes.
- **Warm** regions are periodically accessed by prefetch or session
  keep-alive.  They are good candidates for prefetch optimization.
- **Cold** regions have not been accessed recently.  If they are also
  recomputable, they become eviction candidates.
- **Protected/persistent** regions should never be evicted by Kairo.

The heatmap bridges the gap between per-request I/O class hints and
region-level access dynamics.

## Heat Classes

| Class | Score | Meaning |
|---|---|---|
| HOT | >= 100 | Frequently decoded; never evict |
| WARM | >= 40 | Periodically prefetched; candidate for prefetch |
| COLD | >= 1 | Rarely accessed; eligible for eviction with care |
| EVICTABLE | <= 0 + recompute_ok | Safe to evict; cheap to reconstruct |
| PROTECTED | persistent | Never evict (overrides score) |

## Scoring Model

Each I/O operation adjusts the heat score of the matching region:

| Event | Score delta |
|---|---|
| Decode read hit | +20 |
| Prefetch read hit | +5 |
| Prefill write | +2 |
| Eviction candidate check | -5 |
| Age decay (per interval) | -10 |

The score is a simple saturating counter.  It does not use exponential
moving averages or time-windowed counting (those would be production
improvements).

## Data Structures

### Heatmap entry

```c
struct kairo_kv_heatmap_entry {
    u32 valid;
    u32 region_id;
    u32 model_id;
    u32 session_id;
    u32 cache_pool_id;
    u32 placement_group;
    u64 start_sector;
    u64 nr_sectors;
    enum kairo_kv_heat_class heat_class;
    u64 decode_reads;
    u64 prefetch_reads;
    u64 prefill_writes;
    u64 evictions;
    u64 last_decode_ns;
    u64 last_prefetch_ns;
    u64 last_write_ns;
    bool recompute_ok;
    bool persistent;
    bool protected_region;
    u64 heat_score;
};
```

### Top-level heatmap

```c
struct kairo_kv_heatmap {
    bool enabled;
    u32 nr_regions;
    u64 decay_interval_ns;
    u64 last_decay_ns;
    struct kairo_kv_heatmap_entry regions[KAIRO_KV_HEATMAP_MAX_REGIONS];
    u64 hits;
    u64 misses;
    u64 updates;
    u64 decays;
    u64 evictable_regions;
    u64 protected_regions;
};
```

`KAIRO_KV_HEATMAP_MAX_REGIONS` is fixed at 1024 for RFC/POC.  Real
production would use a dynamic data structure.

## Relationship to Other Stages

### Stage 17: KV Region Hints

The heatmap uses region topology from Stage 17.  Each heatmap entry
maps to a KV region identified by `(model_id, session_id, start_sector)`.
The lookup is a fixed-array linear scan for RFC/POC.

### Stage 18: Recompute-Aware Eviction

The heatmap's `EVICTABLE` and `PROTECTED` classifications feed directly
into Stage 18's eviction scoring.  A region that is heatmap-COLD and
recompute_ok gets a high eviction score.  A region that is heatmap-HOT
gets a negative eviction score (defer eviction).

### Stage 13/14: Decode Latency Feedback

When decode P99 exceeds the target, the heatmap decay interval should
be shortened (more aggressive decay = faster cooling).  This prevents
stale regions from retaining heat scores that would protect them from
eviction during latency crises.

### Stage 12/15: Fairness

Per-session heat weighting could be adjusted by fairness weights.
A noisy session that generates excessive prefetch traffic would have
its prefetch heat contributions de-weighted, preventing it from
artificially protecting its data from eviction.

### Stage 7: Backend Mapping

Warm regions may benefit from faster NVMe placement (e.g., FDP
placement ID assignment).  Cold/evictable regions may be placed on
slower or shared media.

## Benchmark Modeling

The benchmark supports heatmap modeling via:

```
--heatmap-mode none|mock|region
--hot-region-ratio N
--region-reuse-ratio N
--cold-region-ratio N
```

Output fields:

```
heatmap_mode=
hot_region_ratio=
region_reuse_ratio=
cold_region_ratio=
kv_heat_hot=
kv_heat_warm=
kv_heat_cold=
kv_heat_evictable=
kv_heat_protected=
```

The benchmark does **not** fake kernel counter movement.  Heatmap
counter deltas are only meaningful when running on a patched kernel.

## Experiment Cases

| Case | Description |
|---|---|
| `01-no-heatmap` | Baseline without heatmap tracking |
| `02-hot-decode-regions` | High decode ratio, many hot regions |
| `03-cold-recomputable-regions` | Cold regions with recompute_ok |
| `04-mixed-hot-cold-regions` | Balanced mix of hot and cold |
| `05-multisession-heatmap` | Multiple sessions with varying heat |
| `06-eviction-pressure-with-heatmap` | Eviction under heatmap guidance |

## Parser Columns

```
case
heatmap_mode
hot_region_ratio
region_reuse_ratio
cold_region_ratio
decode_p99_us
decode_p95_us
decode_avg_us
evict_MBps
kv_heat_hot
kv_heat_warm
kv_heat_cold
kv_heat_evictable
kv_heat_protected
kairo_kv_heatmap_hits_delta
kairo_kv_heatmap_misses_delta
kairo_kv_heatmap_updates_delta
kairo_kv_heatmap_decays_delta
kairo_kv_heatmap_evictable_regions_delta
kairo_kv_heatmap_protected_regions_delta
```

## WSL Validation Limits

- **Can validate**: benchmark modeling, experiment script, parser,
  WSL dry-run, documentation, repo consistency.
- **Cannot validate**: kernel-side heatmap accounting, sysfs counter
  registration, dispatch-path heat lookup, periodic decay execution,
  classification correctness.

## Patched-Kernel Validation Requirements

To validate actual heatmap behaviour:

1. Build kernel with Kairo patches 0002–0029 applied.
2. Boot on a system with NVMe storage and `CONFIG_BLK_CGROUP` enabled.
3. Run the experiment with `--skip-counters=false` to collect kernel
   heatmap counters.
4. Verify that decode-heavy workloads produce `kairo_kv_heatmap_hits`
   and `kairo_kv_heatmap_hot_regions` counter deltas.
5. Verify that idle/stale regions transition from HOT/WARM to COLD
   over time (heatmap decay).

---

Stage 19 is an RFC/POC KV residency heatmap scaffold.
It does not claim production scalability or correctness.
It does not claim real-time access tracking.
WSL validation verifies benchmark modeling, scripts, parsers, and repo consistency only.
