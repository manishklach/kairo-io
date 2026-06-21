# Benchmark Plan

## Comparison Matrix

Compare the following:

1. baseline Linux scheduler in its default mode
2. baseline `mq-deadline`
3. patched `mq-deadline` with Kairo mode enabled

Sweep across:

- different decode and write thread mixes
- different block sizes
- different SSDs if available

## Primary Metric

- p99 decode-read latency under mixed write pressure

## Secondary Metrics

- average decode-read latency
- write throughput
- aggregate throughput
- CPU overhead
- starvation behavior

## Benchmark Shape

The benchmark should create mixed pressure:

- decode readers: random or strided large-block reads
- prefill writers: sequential large-block writes
- default block size: 1 MiB
- default file size: 8 GiB
- default runtime: 60 seconds

## Example Flow

Baseline:

```bash
./scripts/run_baseline.sh /mnt/nvme/kairo.test nvme0n1
```

Patched:

```bash
echo mq-deadline | sudo tee /sys/block/nvme0n1/queue/scheduler
./scripts/run_kairo_poc.sh /mnt/nvme/kairo.test nvme0n1
```

## What To Look For

- lower p99 decode latency on the patched kernel
- acceptable write throughput degradation for background writes
- no pathological starvation
- stable behavior across repeated runs
