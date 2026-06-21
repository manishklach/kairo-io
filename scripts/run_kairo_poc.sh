#!/usr/bin/env bash
set -euo pipefail

FILE=${1:-/mnt/nvme/kairo.test}
DEV=${2:-nvme0n1}

if [[ -e "/sys/block/${DEV}/queue/scheduler" ]]; then
  echo "scheduler: $(cat /sys/block/${DEV}/queue/scheduler)"
else
  echo "warning: /sys/block/${DEV}/queue/scheduler not found" >&2
fi

BIN=${BIN:-./kairo_bench}
if [[ ! -x "$BIN" ]]; then
  echo "benchmark binary not found: $BIN" >&2
  echo "run: ./scripts/build_bench.sh" >&2
  exit 1
fi

mkdir -p results
OUT="results/kairo_poc_$(date +%Y%m%d_%H%M%S).log"

"$BIN" \
  --file "$FILE" \
  --size ${KAIRO_SIZE:-8G} \
  --block-size ${KAIRO_BLOCK:-1M} \
  --decode-threads ${KAIRO_DECODE_THREADS:-4} \
  --prefetch-threads ${KAIRO_PREFETCH_THREADS:-1} \
  --write-threads ${KAIRO_WRITE_THREADS:-2} \
  --runtime ${KAIRO_RUNTIME:-60} \
  --random-read | tee "$OUT"

echo "wrote $OUT"
