# API Hints

Kairo is not defining a permanent UAPI yet. The current repository only captures experimental hint concepts.

Useful hint channels include:

- `ioprio`
- `O_DIRECT`
- `io_uring`
- registered buffers
- `posix_fadvise()`
- write-life hints

Local classification mapping:

```text
RT prio 0 read  -> KAIRO_DECODE_READ
RT prio 1 read  -> KAIRO_PREFETCH_READ
BE prio 7 write -> KAIRO_PREFILL_WRITE
discard         -> KAIRO_EVICT
```

Future hint plumbing may include:

- `placement_id`
- `session_id`
- `model_id`
- lifetime class
- recomputable flag
