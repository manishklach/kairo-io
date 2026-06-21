#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <block-device>" >&2
  exit 1
fi

DEV="$1"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="results/block-stats/$STAMP"

mkdir -p "$OUT"

uname -a >"$OUT/uname.txt" 2>&1 || true
lsblk >"$OUT/lsblk.txt" 2>&1 || true

if command -v nvme >/dev/null 2>&1; then
  nvme list >"$OUT/nvme-list.txt" 2>&1 || true
fi

if command -v iostat >/dev/null 2>&1; then
  iostat -dx 1 5 "$DEV" >"$OUT/iostat.txt" 2>&1 || true
fi

if command -v fio >/dev/null 2>&1; then
  fio --version >"$OUT/fio-version.txt" 2>&1 || true
fi

if [[ -r "/sys/block/$DEV/queue/scheduler" ]]; then
  cat "/sys/block/$DEV/queue/scheduler" >"$OUT/scheduler.txt" 2>&1 || true
fi

for name in \
  kairo_decode_dispatches \
  kairo_prefetch_dispatches \
  kairo_prefill_dispatches \
  kairo_evict_dispatches \
  kairo_normal_dispatches \
  kairo_starvation_escapes \
  kairo_merge_attempts \
  kairo_merge_successes \
  kairo_hinted_requests \
  kairo_unhinted_requests; do
  if [[ -r "/sys/block/$DEV/queue/iosched/$name" ]]; then
    cat "/sys/block/$DEV/queue/iosched/$name" >"$OUT/$name.txt" 2>&1 || true
  fi
done
