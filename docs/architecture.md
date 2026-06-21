# Kairo Architecture

Kairo is an internal RFC/POC exploring AI KV-cache-aware Linux storage on generic NVMe SSDs.

## Motivation

Decode-critical reads and background prefill writes should not be treated as equivalent traffic when the storage path becomes part of the inference critical path.

## Current Focus

- decode-read prioritization in `mq-deadline`
- temporary `ioprio`-based request classification
- benchmark-driven validation using a pthread benchmark scaffold

## Architecture Overview

```text
decode readers -> ioprio hints -> block request classification -> mq-deadline
prefetch reads -> ioprio hints -> priority lanes             -> generic NVMe
prefill writes -> ioprio hints -> demotion logic             -> SSD queues
```

## I/O Classes

```text
KAIRO_DECODE_READ
KAIRO_PREFETCH_READ
KAIRO_PREFILL_WRITE
KAIRO_EVICT
NORMAL_IO
```

## Local Classification

```text
RT prio 0 read  -> KAIRO_DECODE_READ
RT prio 1 read  -> KAIRO_PREFETCH_READ
BE prio 7 write -> KAIRO_PREFILL_WRITE
discard         -> KAIRO_EVICT
```

## Current Validation Goal

Reduce `decode_p99_us` under mixed prefill-write pressure without collapsing write progress.
