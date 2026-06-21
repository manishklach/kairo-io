# Kairo Bench

This directory contains the pthread-based synthetic benchmark scaffold for Kairo.

## Roles

- decode readers: RT class, prio 0
- prefetch readers: RT class, prio 1
- prefill writers: BE class, prio 7
- evict workers: punch-hole or zeroing fallback to simulate KV-cache cleanup

## Modes

- `decode-only`
- `mixed`
- `prefetch-pressure`
- `eviction-pressure`
- `multisession`

The current benchmark is still a user-space RFC/POC harness, but it now tries
to resemble AI KV-cache storage behavior more closely by separating decode,
prefetch, prefill, and eviction paths, plus model/session fan-out.

## Build

```bash
gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c
```

## Example

```bash
./kairo_bench \
  --file /mnt/nvme/kairo.test \
  --mode mixed \
  --size 8G \
  --block-size 1M \
  --decode-threads 4 \
  --prefetch-threads 1 \
  --write-threads 2 \
  --evict-threads 1 \
  --sessions 4 \
  --models 2 \
  --runtime 60 \
  --random-read
```
