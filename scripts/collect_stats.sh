#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <block-device>" >&2
  exit 1
fi

DEV="$1"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="results/stats/$STAMP"

mkdir -p "$OUT"

echo "[kv-io] collecting stats for $DEV into $OUT"

uname -a >"$OUT/uname.txt" 2>&1 || true
lsblk >"$OUT/lsblk.txt" 2>&1 || true

if command -v fio >/dev/null 2>&1; then
  fio --version >"$OUT/fio-version.txt" 2>&1 || true
fi

if command -v nvme >/dev/null 2>&1; then
  nvme list >"$OUT/nvme-list.txt" 2>&1 || true
  nvme smart-log "/dev/$DEV" >"$OUT/nvme-smart-log.txt" 2>&1 || true
fi

if command -v iostat >/dev/null 2>&1; then
  iostat -dx 1 5 "$DEV" >"$OUT/iostat.txt" || true
fi

if [[ -r "/sys/block/$DEV/queue/scheduler" ]]; then
  cat "/sys/block/$DEV/queue/scheduler" >"$OUT/scheduler.txt" 2>&1 || true
fi

if [[ -d /sys/kernel/debug ]]; then
  find /sys/kernel/debug -maxdepth 3 -iname '*kairo*' -type f -exec sh -c 'for f do cp "$f" "'"$OUT"'"/"$(basename "$f")"; done' sh {} + 2>/dev/null || true
fi
