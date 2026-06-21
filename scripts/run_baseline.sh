#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <file-path> [block-device]" >&2
  exit 1
fi

TARGET_FILE="$1"
BLOCK_DEVICE="${2:-}"

if [[ -n "$BLOCK_DEVICE" ]]; then
  echo "[kairo] baseline scheduler state for $BLOCK_DEVICE"
  cat "/sys/block/$BLOCK_DEVICE/queue/scheduler" || true
fi

./kairo_bench --file "$TARGET_FILE" --mode mixed --size 8G --block-size 1M --decode-threads 4 --prefetch-threads 1 --write-threads 2 --evict-threads 1 --sessions 4 --models 2 --runtime 60 --random-read
