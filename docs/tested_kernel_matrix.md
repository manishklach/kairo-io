# Tested Kernel Matrix

| Kernel version | Foundation apply check | Foundation apply | Foundation symbol validation | `block/mq-deadline.o` build | `block/blk-mq.o` build | Boot tested | Sysfs visible | Counter movement | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Linux 6.8.12 | passed | passed | passed | passed | failed | pending | pending | pending | `scripts/validate_patch_stack.sh`, `apply_foundation_stack.sh`, and `validate_foundation_stack.sh` passed on the local `linux-6.8.12-min` tree. The direct patched `block/mq-deadline.o` build passed. The combined `block/blk-mq.o block/mq-deadline.o` path failed on local `blk-mq.o` `struct blk_plug` member errors that also reproduced outside the Kairo foundation path. Boot and runtime validation remain unrun. |
| Linux 6.8.x (additional trees) | pending | not run | not run | not run | not run | pending | pending | pending | add rows as local validation expands |

## WSL Validation Scope

- Environment: WSL
- Kernel: detected dynamically
- Scope: repo validation + benchmark build + dry-run harness + optional user-space smoke benchmark
- Custom kernel boot: not applicable / not run
- Kairo sysfs counters: not available unless a patched kernel is running
- Physical NVMe placement: not validated

## Stage 7.5 Status

Stage 7.5 (NVMe hook audit and mapping hardening) is a metadata-level
verification pass:

- `docs/stage7_5_nvme_hook_audit.md` — analyzes each 0008 hook point
  against Linux 6.8 real kernel symbols
- `kernel/integration/linux-6.8/audit_nvme_hooks.sh` — programmatic
  audit checking candidate symbol presence
- `scripts/validate_stage7_backend_mapping.py` — validates 0008 sections,
  docs, and benchmark against required patterns
- Integrated into `scripts/validate_patch_stack.sh`
- Benchmark refactored: `kairo_compute_backend_model()` consolidation
- 0008 rewritten with `kairo_backend_caps` abstraction and compile-risk
  annotations

Stage 7.5 does not change foundation status or kernel compilation targets.

## Patch 0010 Stage 8 Tracepoint Status

Stage 8 (kernel observability and tracepoints) is an RFC/POC scaffold:

- `kernel/patches/0010-rfc-kairo-tracepoints-observability.patch`
  defines 9 tracepoints in `include/trace/events/kairo.h`
- Conceptual call sites in block and NVMe layers (not compile-validated)
- bpftrace scripts, experiment harness, trace parser, and audit script
  exist as proof-of-concept tooling
- Not foundation-integrated; requires the full Kairo patch stack for
  tracepoint activation
- Not LKML-ready or stable ABI

## Patch 0008/0009 Stage 7 Mapping Status

Stage 7 (`0008`, `0009`) adds a generic backend mapping scaffold with
feature-detected NVMe hooks. These patches are:

- Metadata-level: `enum kairo_backend_class`, `struct kairo_backend_hint`,
  helpers, and 10 scaffold counters
- Feature-detected: NVMe Streams/FDP/ZNS detection hooks return `false`
  until real detection is wired
- No-op safe: all hooks degrade gracefully when backend support is absent
- Not yet foundation-integrated: Stage 7 remains in the broad RFC/POC patch
  series, not in `kernel/patches/foundation/`
