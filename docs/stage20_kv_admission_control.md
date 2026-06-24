# Stage 20: Flash-Backed KV Admission Control

**Stage 20** adds a conceptual KV-cache admission control scaffold that
decides whether a KV-cache object deserves flash-backed storage.

## Why Not Every KV Object Deserves SSD Space

Traditional caching layers assume all data is equally worth storing.
For KV-cache workloads this is wasteful:

- **Short-lived** objects are evicted before they are ever read back.
  Storing them on flash consumes write endurance for zero benefit.
- **Cold** objects sit on flash consuming space while decode-hot data
  competes for the same capacity.
- **Cheap to recompute** objects can be regenerated from a small amount
  of compute — cheaper than reading them back from flash.
- **Low-priority** objects from noisy or background sessions should not
  crowd out production decode traffic.

Admission control answers: "Should this KV-cache object be stored on
flash, or should the runtime keep it in DRAM / recompute it?"

## Admission vs Eviction

Admission and eviction are complementary:

- **Admission** (Stage 20) prevents unworthy data from ever reaching
  the flash tier.  It is the first gate.
- **Eviction** (Stage 18) reclaims space from data that was admitted
  but later became cold or low-priority.

A good admission policy reduces the need for aggressive eviction.

## Decision Model

### Decision enum

```c
enum kairo_admission_decision {
    KAIRO_ADMIT_UNKNOWN,
    KAIRO_ADMIT_ACCEPT,
    KAIRO_ADMIT_REJECT_SHORT_LIVED,
    KAIRO_ADMIT_REJECT_RECOMPUTE_CHEAP,
    KAIRO_ADMIT_REJECT_COLD,
    KAIRO_ADMIT_REJECT_PRESSURE,
    KAIRO_ADMIT_ACCEPT_MODEL_LOCAL,
    KAIRO_ADMIT_ACCEPT_DECODE_HOT,
    KAIRO_ADMIT_ACCEPT_SHARED,
};
```

### Policy struct

```c
struct kairo_admission_policy {
    bool enabled;
    u64 min_expected_reuse;
    u64 min_lifetime_ms;
    u64 max_decode_p99_us;
    u64 flash_pressure_threshold;
    bool admit_model_local;
    bool admit_session_local;
    bool reject_recompute_cheap;
    bool reject_under_decode_pressure;
};
```

### Request struct

```c
struct kairo_admission_request {
    u32 model_id;
    u32 session_id;
    u32 cache_pool_id;
    u32 region_id;
    u64 object_size_bytes;
    u64 expected_reuse_count;
    u64 expected_lifetime_ms;
    u64 recompute_cost_us;
    bool recompute_ok;
    bool decode_hot;
    bool model_local;
    bool session_local;
    bool shared;
};
```

## Policy Rules (RFC Heuristic)

The decision logic evaluates in priority order:

| Condition | Decision |
|---|---|
| Decode p99 above target AND recomputable | REJECT_PRESSURE |
| Expected lifetime < minimum | REJECT_SHORT_LIVED |
| Recompute_ok AND recompute cost < 100us | REJECT_RECOMPUTE_CHEAP |
| Model local AND expected reuse >= minimum | ACCEPT_MODEL_LOCAL |
| Decode hot | ACCEPT_DECODE_HOT |
| Shared across sessions | ACCEPT_SHARED |
| Expected reuse == 0 AND not model local | REJECT_COLD |
| Fallback | ACCEPT |

## Relationship to Other Stages

### Stage 13/14: Decode Latency Feedback

When decode P99 exceeds `max_decode_p99_us`, recomputable objects are
rejected under pressure.  This prevents additional flash I/O from
competing with decode traffic during latency-sensitive periods.

### Stage 17: KV Region Hints

Region-level metadata (model_id, session_id, region_id, lifetime class)
populates the admission request struct.

### Stage 18: Recompute-Aware Eviction

Objects that admission would have rejected but were admitted anyway
(e.g., under a more permissive policy) become high-priority eviction
candidates in Stage 18.

### Stage 19: Heatmap

Decode-hot objects identified by the heatmap are automatically admitted.
Cold objects are rejected unless they have strong model/session locality.

### Stage 16: blk-cgroup Policy

Per-cgroup admission budgets can be layered on top of the admission
policy — noisy cgroups may have stricter admission thresholds.

### Stage 12/15: Fairness

Model and session weights influence the `min_expected_reuse` threshold.
A high-weight model gets a lower reuse threshold (more data admitted).

## Benchmark Modeling

The benchmark supports admission modeling via:

```
--admission-mode none|mock|policy
--expected-reuse N
--expected-lifetime-ms N
--recompute-cost-us N
--flash-pressure N
```

Output fields:

```
admission_mode=
expected_reuse=
expected_lifetime_ms=
recompute_cost_us=
flash_pressure=
admission_decision=
```

The benchmark models admission decisions based on the policy rules.
It does **not** fake kernel counter movement.

## Experiment Cases

| Case | Description |
|---|---|
| `01-admit-decode-hot` | Decode-hot object admitted |
| `02-reject-short-lived` | Short lifetime rejected |
| `03-reject-recompute-cheap` | Cheap to recompute rejected |
| `04-admit-model-local` | Model-local with high reuse admitted |
| `05-reject-under-pressure` | Under decode pressure, recompute OK rejected |
| `06-admit-shared-cache` | Shared across sessions admitted |

## Parser Columns

```
case
admission_mode
expected_reuse
expected_lifetime_ms
recompute_cost_us
flash_pressure
admission_decision
decode_p99_us
decode_p95_us
decode_avg_us
kairo_admission_requests_delta
kairo_admission_accepts_delta
kairo_admission_rejects_delta
kairo_admission_reject_short_lived_delta
kairo_admission_reject_recompute_cheap_delta
kairo_admission_reject_cold_delta
kairo_admission_reject_pressure_delta
kairo_admission_accept_model_local_delta
kairo_admission_accept_decode_hot_delta
kairo_admission_accept_shared_delta
```

## WSL Validation Limits

- **Can validate**: benchmark modeling, experiment script, parser,
  WSL dry-run, documentation, repo consistency.
- **Cannot validate**: kernel-side admission decisions, sysfs counter
  registration, decode-p99 feedback to admission policy, per-cgroup
  admission budgets.

## Patched-Kernel Validation Requirements

To validate actual admission behaviour:

1. Build kernel with Kairo patches 0002–0030 applied.
2. Boot on a system with NVMe storage and `CONFIG_BLK_CGROUP` enabled.
3. Run the experiment with `--skip-counters=false` to collect kernel
   admission counters.
4. Verify that `kairo_admission_reject_short_lived_delta` appears when
   objects with short lifetimes are submitted.
5. Verify that `kairo_admission_accept_decode_hot_delta` appears for
   decode-hot objects.

---

Stage 20 is an RFC/POC admission control scaffold.
It does not claim production correctness.
It does not claim physical NVMe placement.
It does not claim a stable userspace ABI.
WSL validation verifies benchmark modeling, scripts, parsers, and repo consistency only.
