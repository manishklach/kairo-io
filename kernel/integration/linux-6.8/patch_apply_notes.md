# Linux 6.8 Foundation Patch Apply Notes

This file records local validation results for the compile-targeted Kairo
foundation stack.

## Target

- Linux series: `6.8.x`
- Local tree used for source inspection: `linux-6.8.12-min`
- Foundation stack:
  - `0001-kairo-request-classification.patch`
  - `0002-kairo-mq-deadline-decode-priority.patch`
  - `0003-kairo-prefetch-prefill-evict-policy.patch`
  - `0004-kairo-mq-deadline-sysfs-counters.patch`

## Verified Linux 6.8 symbols and hooks

The foundation patch context was aligned against a real Linux 6.8.12 tree.

- `struct request` includes `unsigned short ioprio`
- `blk_mq_rq_ctx_init()` is the request initialization hook used for
  `kairo_init_request_hints()`
- `req_get_ioprio()`, `rq_data_dir()`, `req_op()`, and `op_is_write()` are
  present with Linux 6.8-compatible names
- `deadline_move_request()`, `dd_dispatch_request()`,
  `dd_dispatch_prio_aged_requests()`, `struct deadline_data`,
  `struct dd_per_prio`, `per_prio->dispatch`, `per_prio->fifo_list`,
  `blk_req_zone_write_lock()`, and `RQF_STARTED` all exist in the inspected
  Linux 6.8.12 tree
- `mq-deadline` sysfs attributes use `struct elv_fs_entry` and the
  `DD_ATTR(...)` pattern

## Validation Log

- fresh sparse git clone of `gregkh/linux` at `v6.8.12` (`6324283`)
  - `scripts/validate_patch_stack.sh <tree>`
  - result: passed
  - `kernel/integration/linux-6.8/apply_foundation_stack.sh --check-only <tree>`
  - result: passed
- `scripts/validate_patch_stack.sh /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min`
  - result: passed
- `kernel/integration/linux-6.8/apply_foundation_stack.sh /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min`
  - result: passed
- `kernel/integration/linux-6.8/validate_foundation_stack.sh /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min`
  - result: passed
- `make -C /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min -j$(nproc) block/mq-deadline.o`
  - result: passed on the patched tree
- `kernel/integration/linux-6.8/build_foundation_objects.sh /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min`
  - result: failed on the combined object target after `make olddefconfig`
  - `make olddefconfig` passed
  - `make -C /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min -j$(nproc) block/blk-mq.o block/mq-deadline.o`
  - result: failed on `block/blk-mq.o`
  - script fallback 1 remains useful:
    `make -C /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min -j$(nproc) block/mq-deadline.o`
  - fallback 1 result: passed on the patched tree
- direct combined build cross-check:
  - `make -C /mnt/c/Users/ManishKL/Documents/Playground/kv-memory-intent/qemu_validation/workdir/linux-6.8.12-min -j$(nproc) block/blk-mq.o block/mq-deadline.o`
  - result: failed on `block/blk-mq.o`
  - the same `block/blk-mq.o` failure reproduces on the unpatched local tree, with `struct blk_plug` member errors (`nr_ios`, `cached_rq`, `mq_list`, `rq_count`, `multiple_queues`, `has_elevator`)
- boot test: pending
- runtime sysfs validation: pending

Update this file only with actual local command output and kernel behavior.
