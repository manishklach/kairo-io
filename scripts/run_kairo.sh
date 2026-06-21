#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <file-path> <fio-job>" >&2
  exit 1
fi

TARGET_FILE="$1"
JOB="$2"
JOB_NAME="$(basename "$JOB" .fio)"

echo "[kairo] POC fio run"
echo "file:   $TARGET_FILE"
echo "job:    $JOB"
echo "mode:   experimental placeholder"

mkdir -p results/raw
fio --filename="$TARGET_FILE" "$JOB" --output="results/raw/kairo-${JOB_NAME}.json" --output-format=json
