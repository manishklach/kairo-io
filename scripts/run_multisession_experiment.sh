#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <file-path> <block-device>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET_FILE="$1"
BLOCK_DEVICE="$2"
BENCH_BIN="$REPO_ROOT/kairo_bench"
OUT_DIR="$REPO_ROOT/results/multisession/$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$OUT_DIR/multisession.log"

mkdir -p "$OUT_DIR"

if [[ ! -x "$BENCH_BIN" ]]; then
  "$REPO_ROOT/scripts/build_bench.sh"
fi

"$REPO_ROOT/scripts/set_mq_deadline.sh" "$BLOCK_DEVICE"
"$REPO_ROOT/scripts/collect_kairo_counters.sh" "$BLOCK_DEVICE" "$OUT_DIR/counters-before" || true

"$BENCH_BIN" \
  --file "$TARGET_FILE" \
  --mode multisession \
  --size 8G \
  --block-size 1M \
  --decode-threads 6 \
  --prefetch-threads 3 \
  --write-threads 2 \
  --evict-threads 1 \
  --sessions 8 \
  --models 4 \
  --runtime 60 \
  --random-read | tee "$LOG_FILE"

"$REPO_ROOT/scripts/collect_kairo_counters.sh" "$BLOCK_DEVICE" "$OUT_DIR/counters-after" || true

echo "[kairo] multisession results saved in $OUT_DIR"
