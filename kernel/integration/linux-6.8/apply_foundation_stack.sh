#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-source-tree>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches/foundation"
LINUX_TREE="$1"

foundation_patches=(
  "$PATCH_DIR/0001-kairo-request-classification.patch"
  "$PATCH_DIR/0002-kairo-mq-deadline-decode-priority.patch"
  "$PATCH_DIR/0003-kairo-prefetch-prefill-evict-policy.patch"
  "$PATCH_DIR/0004-kairo-mq-deadline-sysfs-counters.patch"
)

required_files=(
  "$LINUX_TREE/block/mq-deadline.c"
  "$LINUX_TREE/block/blk-mq.c"
  "$LINUX_TREE/include/linux/blk-mq.h"
  "$LINUX_TREE/include/linux/blk_types.h"
)

if [[ ! -d "$LINUX_TREE" ]]; then
  echo "[kairo] Linux source tree not found: $LINUX_TREE" >&2
  exit 1
fi

for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[kairo] required Linux file missing: $file" >&2
    exit 1
  fi
done

for patch in "${foundation_patches[@]}"; do
  if [[ ! -f "$patch" ]]; then
    echo "[kairo] missing foundation patch: $patch" >&2
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

echo "[kairo] checking foundation stack against: $LINUX_TREE"
for patch in "${foundation_patches[@]}"; do
  echo "[kairo] git apply --check $(basename "$patch")"
  if ! git -C "$scratch_dir" apply --check --recount "$patch"; then
    echo "[kairo] apply check failed for $(basename "$patch")" >&2
    exit 1
  fi

  git -C "$scratch_dir" apply --recount "$patch"
done

echo "[kairo] all checks passed; applying foundation stack"
for patch in "${foundation_patches[@]}"; do
  echo "[kairo] applying $(basename "$patch")"
  (
    cd /tmp
    git apply --unsafe-paths --recount --directory="$LINUX_TREE" "$patch"
  )
done

echo "[kairo] foundation stack applied successfully"
