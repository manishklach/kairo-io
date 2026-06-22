# Stage 7.5: NVMe Hook-Point Audit for Linux 6.8

## Objective

Audit every hook point that the 0008 (RFC/POC) patch introduces into the
Linux 6.8 kernel tree. For each hook point, identify:

- The exact file and nearby real kernel symbols
- Whether the hook is a **compile-target candidate** (could compile if
  ported to a real kernel tree) or a **conceptual hook** (demonstrates
  architecture but would need significant rework to compile)
- The compile risk (low/medium/high)
- What would need to change to make it compile

This audit mirrors what `audit_nvme_hooks.sh` checks programmatically.

---

## File-by-File Audit

### A. `include/linux/blk_types.h` — Backend Class Enum and Hint Structure

**Hook points in 0008:**

1. `enum kairo_backend_class` (lines 45-52 of patch diff)
2. `struct kairo_backend_hint` (lines 64-72)
3. `KAIRO_BACKEND_F_*` flags (lines 75-79)
4. Added field inside existing `struct kairo_request_hints` (line 86)

**Nearby real kernel symbols:**
- `struct request` — the main I/O request structure, defined in this header
- `struct bio` — block I/O bio
- `enum req_opf` — operation flags
- `enum rq_end_io_ret` — end-IO return values
- `struct blk_rq_stats` — request statistics

**Classification: COMPILE-TARGET CANDIDATE**

**Compile risk: LOW**

**Rationale:**
- Adding an enum and a struct to this header is trivial — no dependencies
  on other kernel subsystems, no inline function changes needed.
- The addition of `struct kairo_backend_hint` as a field inside
  `struct kairo_request_hints` is safe because `kairo_request_hints`
  is already a Kairo-introduced structure (from Stage 1/2), so the
  compiler never sees it unless the Kairo patch stack is applied.

**What would change for compile-target:**
- None. The current diff is already a clean compile-target addition.

---

### B. `include/linux/blk-mq.h` — Generic Backend Mapping Helpers

**Hook points in 0008:**

1. `kairo_backend_class_from_request()` (lines 101-119)
2. `kairo_backend_hint_from_request()` (lines 121-135)
3. `kairo_backend_is_noop()` (lines 137-141)
4. `kairo_backend_is_recomputable()` (lines 143-147)

**Nearby real kernel symbols:**
- `struct request_queue` — the request queue, defined via forward decl
- `blk_mq_rq_to_pdu()` — converts request to driver-specific PDU
- `blk_mq_unique_tag()` — generates unique tag for a request
- Many `static inline` helper functions for blk-mq

**Classification: COMPILE-TARGET CANDIDATE**

**Compile risk: LOW**

**Rationale:**
- These are `static inline` functions that reference `struct request`
  fields (`kairo_hints.placement.lifetime_class`, etc.). Since those
  fields are also Kairo-introduced, the compiler never sees them
  unless the full Kairo stack is applied.
- No external kernel symbols are referenced.
- The switch on `lifetime_class` is compact and deterministic.

**What would change for compile-target:**
- None. These are already clean compile-target additions.

---

### C. `include/linux/nvme.h` — NVMe Kairo Mapping Structure

**Hook points in 0008:**

1. `struct nvme_kairo_mapping` (lines 162-166)

**Nearby real kernel symbols:**
- `struct nvme_command` — the main NVMe command structure
- `struct nvme_id_ctrl` — NVMe identify controller data
- `struct nvme_streams_directive_params` — Streams directive parameters
- `enum nvme_opcode` — NVMe command opcodes
- `struct nvme_sgl_desc` — scatter-gather list descriptor

**Classification: CONCEPTUAL HOOK**

**Compile risk: LOW**

**Rationale:**
- This structure is already present in the Stage 7 patch and is used by
  the legacy `nvme_kairo_select_mapping()` path. It's a small data
  structure (3 fields) that does not reference any external kernel type.
- It would compile cleanly on any kernel version.
- It remains a conceptual hook because the fields are not yet populated
  by real NVMe identify-command data.

**What would change for compile-target:**
- None. Already clean. However, to make the fields meaningful, the
  caller would need to populate `streamid` from real
  `NVME_STREAMS_DIRECTIVE_PARAMS` and `phandle` from real FDP
  identify data.

---

### D. `drivers/nvme/host/nvme.h` — NVMe Feature-Detection Hooks

**Hook points in 0008:**

1. `nvme_kairo_streams_supported()` (lines 179-182)
2. `nvme_kairo_fdp_supported()` (lines 184-187)
3. `nvme_kairo_zns_supported()` (lines 189-192)

**Nearby real kernel symbols:**
- `struct nvme_ctrl` — the main NVMe controller structure, defined here
  with fields like `nr_streams`, `nr_ruhs` (number of RUH/FDP contexts)
- `struct nvme_ns` — namespace structure with `head` and `ns_id`
- `struct nvme_request` — driver-specific request wrapper
- `nvme_alloc_request()` — allocates an NVMe request
- `nvme_setup_cmd()` — sets up an NVMe command
- `nvme_complete_rq()` — completes a request

**Classification: CONCEPTUAL HOOK**

**Compile risk: LOW** (as no-ops); **MEDIUM** (when wired to real detection)

**Rationale:**
- As no-ops returning `false`, these compile trivially and are safe.
- When wired to real detection (e.g., checking `ctrl->nr_streams > 0`,
  reading FDP identify data, checking ZNS capability), the compile risk
  is medium because:
  - `ctrl->nr_streams` is already a real kernel field (Linux 6.8)
  - FDP identify read would need `nvme_identify_ctrl()` or similar
  - ZNS checks would need `ns->head->ids` or similar

**What would change for compile-target:**
- Keep as no-ops for now. When wiring detection:
  - `nvme_kairo_streams_supported`: check `ctrl->nr_streams > 0`
    and `ctrl->sgls & NVME_CTRL_SGLS_ENABLE`
  - `nvme_kairo_fdp_supported`: check `ctrl->nr_ruhs > 0`
    (FDP/RUH count from identify)
  - `nvme_kairo_zns_supported`: check namespace type via
    `ns->head->ids.ns_id` zoned info or `ns->head->features`

---

### E. `drivers/nvme/host/core.c` — Backend Preparation and Application

**Hook points in 0008:**

1. `nvme_kairo_prepare_backend_hint()` (lines 207-226)
2. `nvme_kairo_apply_backend_hint()` (lines 228-241)
3. Call site in existing `nvme_setup_cmd()` or similar (lines 255-260)
4. `nvme_kairo_select_mapping()` — legacy mapping (lines 247-249)

**Nearby real kernel symbols:**
- `nvme_setup_cmd()` — the main NVMe command setup function
- `nvme_setup_rw()` — read/write command setup (calls `nvme_setup_cmd`)
- `nvme_alloc_request()` — request allocation
- `nvme_pci_setup_prps()` — PRP list setup
- `struct nvme_ctrl` — with `nr_streams`, `nr_ruhs` fields
- `nvme_start_ctrl()` / `nvme_stop_ctrl()` — controller lifecycle

**Classification: CONCEPTUAL HOOK**

**Compile risk: MEDIUM**

**Rationale:**
- The prepare/apply functions themselves are self-contained and compile
  cleanly (they only reference Kairo types and the no-op detection
  helpers from nvme.h).
- The **call site** (inserted into `nvme_setup_cmd` or similar) has
  medium risk because it needs to be placed at exactly the right point
  in command setup — after the command is allocated but before it is
  submitted. The exact location depends on kernel version.
- The legacy `nvme_kairo_select_mapping` call site already exists and
  compiles, so the new call site is the risk point.

**What would change for compile-target:**
- The call site insertion point is version-sensitive. On Linux 6.8,
  the correct location is inside `nvme_setup_cmd()` after
  `nvme_setup_rw()` succeeds but before the command is issued.
- The prepare/apply functions themselves need no changes.
- Need to verify that `ctrl->nr_streams` / `ctrl->nr_ruhs` checks
  guard the new backend path correctly (they already guard the
  legacy path, so should be safe).

---

### F. `drivers/nvme/host/zns.c` — ZNS Zone Reset Candidate

**Hook points in 0008:**

1. `nvme_kairo_zone_reset_candidate()` (lines 283-286)

**Nearby real kernel symbols:**
- `nvme_setup_zone_append()` — zone append command setup
- `nvme_zone_mgmt_reset()` — zone reset management
- `nvme_zone_check()` — zone state validation
- `struct nvme_zone_info` — zone information
- `nvme_zns_fill_zone_info()` — populate zone info from identify

**Classification: CONCEPTUAL HOOK**

**Compile risk: LOW**

**Rationale:**
- The function is a simple predicate checking Kairo metadata fields.
- It does not reference any ZNS-specific kernel symbols directly.
- It would compile on any kernel, even without ZNS support (though
  it would never be called if ZNS is not configured).

**What would change for compile-target:**
- None for the function itself. However, the call site (presumably in
  a zone reset or zone management path) is not yet wired in 0008, so
  the function is currently dead code. To wire it, the caller would
  need to be in `nvme_zone_mgmt_reset()` or equivalent.

---

## Hook-Point Classification Summary

| Section | File | Hook | Classification | Compile Risk | Depends On |
|---------|------|------|----------------|--------------|------------|
| A | `blk_types.h` | `enum kairo_backend_class` | compile-target | low | nothing |
| A | `blk_types.h` | `struct kairo_backend_hint` | compile-target | low | nothing |
| A | `blk_types.h` | `KAIRO_BACKEND_F_*` flags | compile-target | low | nothing |
| B | `blk-mq.h` | backend helper inlines | compile-target | low | Stage 6 fields |
| C | `nvme.h` (include/linux) | `nvme_kairo_mapping` | conceptual | low | nothing |
| D | `nvme.h` (driver) | `nvme_kairo_*_supported()` | conceptual | low (no-op) / medium (wired) | `ctrl->nr_streams`, `ctrl->nr_ruhs` |
| E | `core.c` | `nvme_kairo_prepare_backend_hint()` | conceptual | medium | D, A, B |
| E | `core.c` | `nvme_kairo_apply_backend_hint()` | conceptual | medium | D, A, B |
| E | `core.c` | call site in `nvme_setup_cmd()` | conceptual | medium | version-sensitive |
| F | `zns.c` | `nvme_kairo_zone_reset_candidate()` | conceptual | low | nothing (dead code until wired) |

---

## Proposed kairo_backend_caps Abstraction

The audit reveals that the current per-feature `_supported()` helpers
(Section D) are the main abstraction boundary that should be replaced
by a unified `kairo_backend_caps` struct:

```c
struct kairo_backend_caps {
    bool streams : 1;
    bool fdp     : 1;
    bool zns     : 1;
};
```

With a single detection function:

```c
struct kairo_backend_caps nvme_kairo_get_backend_caps(struct request_queue *q);
```

This replaces:

```c
bool nvme_kairo_streams_supported(struct request_queue *q);
bool nvme_kairo_fdp_supported(struct request_queue *q);
bool nvme_kairo_zns_supported(struct request_queue *q);
```

**Rationale:**
- Single function call instead of three — cleaner in the hot path
- Caps struct can be cached per-queue (future optimization)
- Easier to add new capability bits (e.g., endurance groups)
- Maps naturally to the `KAIRO_BACKEND_F_*` flags in the hint struct

**Compile risk of refactor: LOW** — the caps struct is a simple POD type,
and the refactor is a mechanical replacement in `nvme_kairo_prepare_backend_hint()`.

---

## Compile-Risk Annotation Convention

Each hook in the rewritten 0008 will carry an annotation comment:

| Annotation | Meaning |
|------------|---------|
| `/* COMPILE-TARGET: <reason> */` | Would compile on stock Linux 6.8 with Kairo foundation applied |
| `/* CONCEPTUAL-HOOK: <reason> */` | Demonstrates architecture; needs rework to compile |
| `/* VERSION-SENSITIVE: <details> */` | Call site depends on exact kernel version |

---

## Audit Script

A companion script `kernel/integration/linux-6.8/audit_nvme_hooks.sh`
checks for the presence of these hook points in a real Linux 6.8 tree
by searching for candidate symbols (the nearby real kernel symbols
listed above) and verifying that the Kairo-added symbols are absent
from stock (confirming that the hooks are Kairo-only additions).
