# Kernel Patch Plan

Kairo uses a local RFC/POC patch series shape rather than a submission-oriented kernel series.

## Likely Files

- `block/mq-deadline.c`
- `block/blk-mq.c`
- `block/blk-merge.c`
- `block/blk-ioprio.c`
- `include/linux/blk_types.h`
- `include/linux/blk-mq.h`
- `include/uapi/linux/ioprio.h`
- `fs/io_uring/`
- `drivers/nvme/host/core.c`
- `drivers/nvme/host/zns.c`

## Patch Sequence

```text
0001: mq-deadline decode-priority lane
0002: block-layer KVIO request classification helpers
0003: debugfs/sysfs stats for KVIO dispatch
0004: prefetch-aware scheduling
0005: large-block merge preference for KVIO reads
0006: lifetime/placement hint plumbing
0007: optional NVMe/ZNS backend mapping
```

## Notes

- `0001` is the first aggressive scheduler-side validation step.
- `0002` formalizes internal classification concepts.
- `0003` improves observability for local tuning.
- later patches expand from decode-read priority toward the broader architecture.
