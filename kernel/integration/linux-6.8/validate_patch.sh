#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-source-tree>" >&2
  exit 1
fi

LINUX_TREE="$1"
TARGET_FILE="$LINUX_TREE/block/mq-deadline.c"

if [[ ! -f "$TARGET_FILE" ]]; then
  echo "[kairo] expected file missing: $TARGET_FILE" >&2
  exit 1
fi

required_symbols=(
  "kairo_enable"
  "kairo_decode_budget"
  "dd_kairo_is_decode_read"
  "kairo_decode_dispatches"
  "kairo_normal_dispatches"
  "kairo_starvation_escapes"
)

missing=0
for symbol in "${required_symbols[@]}"; do
  if grep -q "$symbol" "$TARGET_FILE"; then
    echo "[kairo] found symbol: $symbol"
  else
    echo "[kairo] missing symbol: $symbol" >&2
    missing=1
  fi
done

if [[ $missing -ne 0 ]]; then
  echo "[kairo] patch validation failed" >&2
  exit 1
fi

echo "[kairo] patch validation passed"
