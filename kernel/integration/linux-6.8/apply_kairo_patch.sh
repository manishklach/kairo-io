#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-source-tree>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches"
LINUX_TREE="$1"

foundation_patches=(
  "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"
  "$PATCH_DIR/0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"
)

if [[ ! -d "$LINUX_TREE" ]]; then
  echo "[kairo] Linux source tree not found: $LINUX_TREE" >&2
  exit 1
fi

if [[ ! -f "$LINUX_TREE/block/mq-deadline.c" || ! -f "$LINUX_TREE/block/blk-mq.c" ]]; then
  echo "[kairo] expected block-layer files are missing in $LINUX_TREE" >&2
  exit 1
fi

for patch in "${foundation_patches[@]}"; do
  if [[ ! -f "$patch" ]]; then
    echo "[kairo] patch not found: $patch" >&2
    exit 1
  fi
done

scratch_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$scratch_dir"
}
trap cleanup EXIT

mkdir -p "$scratch_dir/block" "$scratch_dir/include/linux"
cp "$LINUX_TREE/block/mq-deadline.c" "$scratch_dir/block/mq-deadline.c"
cp "$LINUX_TREE/block/blk-mq.c" "$scratch_dir/block/blk-mq.c"
cp "$LINUX_TREE/include/linux/blk-mq.h" "$scratch_dir/include/linux/blk-mq.h"
cp "$LINUX_TREE/include/linux/blk_types.h" "$scratch_dir/include/linux/blk_types.h"

for patch in "${foundation_patches[@]}"; do
  echo "[kairo] checking patch applicability: $(basename "$patch")"
  if ! git -C "$scratch_dir" apply --check "$patch"; then
    echo "[kairo] patch check failed: $(basename "$patch")" >&2
    exit 1
  fi

  git -C "$scratch_dir" apply "$patch"
done

for patch in "${foundation_patches[@]}"; do
  echo "[kairo] applying patch: $(basename "$patch")"
  if ! git -C "$LINUX_TREE" apply "$patch"; then
    echo "[kairo] patch apply failed: $(basename "$patch")" >&2
    exit 1
  fi
done

echo "[kairo] Stage 1 foundation stack applied successfully"
