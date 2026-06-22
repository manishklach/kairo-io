#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <block-device> [output-dir]" >&2
  exit 1
fi

DEV="$1"
OUT_DIR="${2:-results/counters/$(date +%Y%m%d-%H%M%S)}"
IOSCHED_DIR="/sys/block/$DEV/queue/iosched"

mkdir -p "$OUT_DIR"

counter_names=(
  # tunables
  kairo_enable
  kairo_decode_budget
  kairo_prefetch_budget
  kairo_prefetch_deadline_us
  kairo_large_read_kb
  kairo_merge_bias_enable

  # dispatch counters
  kairo_decode_dispatches
  kairo_prefetch_dispatches
  kairo_prefetch_deadline_hits
  kairo_prefetch_budget_skips
  kairo_prefill_dispatches
  kairo_prefill_demotion_observations
  kairo_evict_dispatches
  kairo_evict_demotion_observations
  kairo_normal_dispatches
  kairo_starvation_escapes

  # merge instrumentation
  kairo_merge_attempts
  kairo_merge_successes
  kairo_merge_rejects
  kairo_decode_merge_attempts
  kairo_decode_merge_successes
  kairo_prefetch_merge_attempts
  kairo_prefetch_merge_successes

  # request-size counters
  kairo_small_decode_reads
  kairo_large_decode_reads
  kairo_small_prefetch_reads
  kairo_large_prefetch_reads

  # request-size histogram
  kairo_decode_read_4k
  kairo_decode_read_16k
  kairo_decode_read_64k
  kairo_decode_read_256k
  kairo_decode_read_1m
  kairo_decode_read_4m
  kairo_decode_read_gt4m
  kairo_prefetch_read_4k
  kairo_prefetch_read_16k
  kairo_prefetch_read_64k
  kairo_prefetch_read_256k
  kairo_prefetch_read_1m
  kairo_prefetch_read_4m
  kairo_prefetch_read_gt4m

  # general hint counters
  kairo_hinted_requests
  kairo_unhinted_requests
  kairo_ioprio_hinted_requests
  kairo_rwf_hinted_requests
  kairo_bio_hinted_requests
  kairo_hint_fallback_requests
  kairo_ephemeral_requests
  kairo_recomputable_requests
  kairo_no_durability_requests
  kairo_avoid_pagecache_requests
  kairo_evict_cleanup_requests
)

for name in "${counter_names[@]}"; do
  if [[ -r "$IOSCHED_DIR/$name" ]]; then
    cat "$IOSCHED_DIR/$name" | tee "$OUT_DIR/$name.txt"
  fi
done
