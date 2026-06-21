# Results

This directory is intentionally empty by default.

Do not commit benchmark numbers here unless the run is reproducible and the
inputs are auditable by a reviewer.

## Suggested Layout

- `raw/` for direct benchmark outputs such as `fio` JSON
- `stats/` for `iostat`, `nvme-cli`, trace, and debug snapshots
- summary plots or markdown reports committed only after runs are reproducible

## Required Methodology Record

Every committed result set should include, at minimum:

- exact kernel version
  - example: `Linux 6.8.12`
- repository commit SHA
- whether Kairo patches were applied
  - if yes, list the exact patch stack or branch/commit used
- NVMe model
- NVMe firmware revision
- drive capacity and namespace layout if relevant
- host CPU and memory configuration
- scheduler configuration
  - scheduler name
  - any Kairo sysfs tunables changed from default
- filesystem and mount options
- benchmark command line
  - `bench/kairo_bench.c` invocation or wrapper script invocation
- `fio` command line and job file
  - if `fio` is used for comparison or interference generation
- number of runs
  - single-run numbers should be labeled clearly as such
- warmup/cooldown policy
- source paths to raw logs, counter snapshots, and trace artifacts

## Minimum Reproducibility Checklist

When publishing numbers, record:

- SSD model
- kernel version
- scheduler configuration
- benchmark parameters
- `fio` parameters, if used
- number of repeated runs
- whether KV-aware kernel patches were applied

## Example Report Fields

A result report should make it possible for a reviewer to answer:

- Which kernel tree and commit produced this result?
- Which exact Kairo patch stack was present?
- Which NVMe device and firmware was tested?
- How many benchmark runs were executed?
- Which run statistics were kept and which were discarded?
- Where are the raw logs and before/after counter snapshots?

## Recommended Companion Files

For each published result set, include:

- a markdown summary report
- raw `kairo_bench` output
- any `fio` output used in the same experiment
- before/after Kairo sysfs counter snapshots
- block-layer trace or latency trace artifacts if they informed conclusions
