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
  kairo_enable
  kairo_decode_budget
  kairo_decode_dispatches
  kairo_prefetch_dispatches
  kairo_prefill_dispatches
  kairo_evict_dispatches
  kairo_normal_dispatches
  kairo_starvation_escapes
  kairo_merge_attempts
  kairo_merge_successes
  kairo_hinted_requests
  kairo_unhinted_requests
)

for name in "${counter_names[@]}"; do
  if [[ -r "$IOSCHED_DIR/$name" ]]; then
    cat "$IOSCHED_DIR/$name" | tee "$OUT_DIR/$name.txt"
  fi
done
