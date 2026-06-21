# Kairo Bench

This directory contains the pthread-based synthetic benchmark scaffold for Kairo.

## Roles

- decode readers: RT class, prio 0
- prefetch readers: RT class, prio 1
- prefill writers: BE class, prio 7

## Build

```bash
gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c
```

## Example

```bash
./kairo_bench \
  --file /mnt/nvme/kairo.test \
  --size 8G \
  --block-size 1M \
  --decode-threads 4 \
  --prefetch-threads 1 \
  --write-threads 2 \
  --runtime 60 \
  --random-read
```
