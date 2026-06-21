#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-source-tree>" >&2
  exit 1
fi

LINUX_TREE="$1"
MQ_DEADLINE_FILE="$LINUX_TREE/block/mq-deadline.c"
BLK_TYPES_FILE="$LINUX_TREE/include/linux/blk_types.h"
BLK_MQ_FILE="$LINUX_TREE/include/linux/blk-mq.h"

if [[ ! -f "$MQ_DEADLINE_FILE" || ! -f "$BLK_TYPES_FILE" || ! -f "$BLK_MQ_FILE" ]]; then
  echo "[kairo] expected Kairo foundation files are missing in $LINUX_TREE" >&2
  exit 1
fi

mq_deadline_symbols=(
  "kairo_enable"
  "kairo_decode_budget"
  "kairo_decode_dispatches"
  "kairo_prefetch_dispatches"
  "kairo_prefill_dispatches"
  "kairo_evict_dispatches"
  "kairo_normal_dispatches"
  "kairo_starvation_escapes"
  "kairo_hinted_requests"
  "kairo_unhinted_requests"
)

blk_types_symbols=(
  "enum kairo_io_class"
  "struct kairo_request_hints"
  "kairo_deadline_ns"
  "kairo_prefetch_distance"
)

blk_mq_symbols=(
  "kairo_init_request_hints"
  "kairo_classify_rq"
  "kairo_is_decode_read"
  "kairo_is_prefetch_read"
  "kairo_is_prefill_write"
  "kairo_is_evict"
  "kairo_hints"
)

missing=0
for symbol in "${mq_deadline_symbols[@]}"; do
  if grep -q "$symbol" "$MQ_DEADLINE_FILE"; then
    echo "[kairo] found mq-deadline symbol: $symbol"
  else
    echo "[kairo] missing mq-deadline symbol: $symbol" >&2
    missing=1
  fi
done

for symbol in "${blk_types_symbols[@]}"; do
  if grep -q "$symbol" "$BLK_TYPES_FILE"; then
    echo "[kairo] found blk_types symbol: $symbol"
  else
    echo "[kairo] missing blk_types symbol: $symbol" >&2
    missing=1
  fi
done

for symbol in "${blk_mq_symbols[@]}"; do
  if grep -q "$symbol" "$BLK_MQ_FILE"; then
    echo "[kairo] found blk-mq symbol: $symbol"
  else
    echo "[kairo] missing blk-mq symbol: $symbol" >&2
    missing=1
  fi
done

if [[ $missing -ne 0 ]]; then
  echo "[kairo] foundation patch validation failed" >&2
  exit 1
fi

echo "[kairo] foundation patch validation passed"
