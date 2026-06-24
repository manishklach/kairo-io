# Stage 18: Recompute-Aware Eviction Scheduler

**Stage 18** adds a conceptual eviction-class model and eviction-scoring
scaffold to Kairo.  It introduces the idea that the kernel storage stack
should understand *which cache data is cheap to reconstruct* and
prioritise eviction accordingly.

## Why AI KV-Cache Eviction Is Not Ordinary Delete/Discard

Traditional block-layer eviction (discard, writeback-triggered reclaim)
treats all data uniformly.  For KV-cache workloads this is wrong:

- **Recomputable short-lived** data can be regenerated from a small
  amount of compute.  Evicting it is cheap.
- **Session-scoped cache** eviction forces a session-level recompute.
  It is more expensive.
- **Model-local cache** is shared across sessions; evicting it impacts
  all sessions of the same model.
- **Persistent / durable** data should never be evicted by the I/O
  scheduler under normal pressure.

Kairo's eviction-class model encodes this hierarchy so that the kernel
can make informed eviction decisions.

## Recomputable vs Non-Recomputable

The key innovation of Stage 18 is **recompute awareness**:

| Data type | Recompute cost | Preferred eviction |
|---|---|---|
| Recomputable short-lived | Very low | Always preferred |
| Ephemeral prefetch | Low (speculative) | Preferred |
| Recomputable session | Moderate | Preferred over non-recompute |
| Session cache | Medium | Evict only if needed |
| Model cache | High | Avoid |
| Persistent | Very high | Never (except starvation escape) |

## Eviction Scoring

Each request is assigned an eviction score.  Higher scores indicate
safer / cheaper eviction candidates.

### Base scores

| Class | Score |
|---|---|
| Recomputable short-lived | +100 |
| Ephemeral prefetch | +90 |
| Recomputable session | +80 |
| Ordinary session cache | +50 |
| Model-local cache | +20 |
| Persistent / durable | -1000 (defer) |

### Penalty modifiers (conceptual, not wired)

| Condition | Penalty |
|---|---|
| Decode-hot data | -500 |
| Recently accessed | -100 |

### Eviction class enum

```c
enum kairo_eviction_class {
    KAIRO_EVICT_NONE = 0,
    KAIRO_EVICT_RECOMPUTABLE_SHORT,
    KAIRO_EVICT_RECOMPUTABLE_SESSION,
    KAIRO_EVICT_EPHEMERAL_PREFETCH,
    KAIRO_EVICT_SESSION_CACHE,
    KAIRO_EVICT_MODEL_CACHE,
    KAIRO_EVICT_PERSISTENT_AVOID,
};
```

### Eviction decision struct

```c
struct kairo_eviction_decision {
    enum kairo_eviction_class eviction_class;
    u32 model_id;
    u32 session_id;
    u32 cache_pool_id;
    u32 placement_group;
    bool recompute_ok;
    bool ephemeral;
    bool persistent_avoid;
    bool discard_preferred;
    bool writeback_required;
    u64 score;
    u64 reason_flags;
};
```

## Interaction with Decode P99 Controller

When decode latency P99 exceeds the target, eviction pressure should be
reduced — evicting decode-hot data during high-latency periods makes
the latency problem worse.

The conceptual policy:

- **Decode p99 healthy (< target)**: eviction proceeds normally.
- **Decode p99 elevated (> target)**: eviction of decode-hot data is
  deferred.  Recomputable short-lived data may still be evicted.
- **Decode p99 critical (>> target)**: all eviction is paused except
  starvation-escape eviction.

This policy is **documented but not wired** in Stage 18.

## Interaction with Fairness

Fairness (Stage 12) assigns per-model and per-session weights.  The
eviction policy should respect these weights:

- A noisy session that generates excessive prefetch should see its
  prefetch data evicted first.
- A well-behaved session with decode-hot data should have its data
  deferred from eviction.

These interactions are future work.

## Benchmark Modeling

The benchmark supports eviction policy modeling via:

```
--eviction-policy none|recompute-aware|lifetime|mixed
--eviction-pressure N
```

Output fields:

```
eviction_policy=
eviction_recompute_ok=
eviction_lifetime=
eviction_score_model=
eviction_pressure=
```

The benchmark does **not** fake kernel counter movement.  Eviction
counter deltas (e.g. `kairo_eviction_decisions_delta`) are only
meaningful when running on a patched kernel.

## Experiment Cases

| Case | Description |
|---|---|
| `01-ordinary-eviction` | No eviction policy; baseline |
| `02-recomputable-short-lived` | Recompute-aware policy, moderate pressure |
| `03-recomputable-session-cache` | Recompute-aware, higher pressure |
| `04-model-cache-avoid` | Lifetime policy, high pressure |
| `05-decode-pressure-eviction-defer` | Mixed policy with decode pressure |
| `06-mixed-eviction-pressure` | Mixed policy, high pressure, many threads |

## Parser Columns

```
case
eviction_policy
eviction_recompute_ok
eviction_lifetime
eviction_pressure
decode_p99_us
decode_p95_us
decode_avg_us
write_MBps
evict_MBps
kairo_eviction_decisions_delta
kairo_eviction_recomputable_short_delta
kairo_eviction_recomputable_session_delta
kairo_eviction_ephemeral_prefetch_delta
kairo_eviction_session_cache_delta
kairo_eviction_model_cache_delta
kairo_eviction_persistent_avoided_delta
kairo_eviction_decode_hot_deferred_delta
kairo_eviction_discard_preferred_delta
kairo_eviction_writeback_required_delta
```

## WSL Validation Limits

- **Can validate**: benchmark modeling, experiment script, parser,
  WSL dry-run, documentation, repo consistency.
- **Cannot validate**: kernel-side eviction decisions, sysfs counter
  registration, dispatch-path eviction integration, decode-latency
  feedback to eviction policy.

## Patched-Kernel Validation Requirements

To validate actual eviction behaviour:

1. Build kernel with Kairo patches 0002–0028 applied.
2. Boot on a system with NVMe storage and `CONFIG_BLK_CGROUP` enabled.
3. Run the experiment with `--skip-counters=false` to collect kernel
   eviction counters.
4. Verify that `kairo_eviction_recomputable_short_delta` is
   proportionally higher than `kairo_eviction_model_cache_delta`
   under eviction pressure.

---

Stage 18 is an RFC/POC eviction policy scaffold.
It does not claim production eviction correctness.
It does not claim physical NVMe placement.
WSL validation verifies benchmark modeling, scripts, parsers, and repo consistency only.
