# Kairo bpftrace Helpers

This directory contains simple tracing helpers for independent observation of
block latency during Kairo experiments.

## `trace_block_latency.bt`

This script uses common block tracepoints:

- `block:block_rq_issue`
- `block:block_rq_complete`

It prints one line per completed request with:

- device identifier
- sector
- `rwbs`
- request latency in microseconds

## Example

```bash
sudo bpftrace tools/bpf/trace_block_latency.bt
```

Run it in parallel with:

```bash
./scripts/validate_kairo_runtime.sh /mnt/nvme/kairo.test nvme0n1
./scripts/run_ab_experiment.sh /mnt/nvme/kairo.test nvme0n1
```

Notes:

- this is a lightweight local POC trace, not a full attribution pipeline
- field layouts can vary slightly across kernels, so validate on the target host
- use it to compare read and write latency shape under baseline vs Kairo runs
