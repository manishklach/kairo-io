#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches"
LINUX_TREE="${1:-}"

required_patches=(
  "0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "0002-rfc-kairo-request-classification.patch"
  "0003-rfc-kairo-io-uring-hint-plumbing.patch"
  "0004-rfc-kairo-large-block-coalescing.patch"
  "0005-rfc-kairo-prefetch-deadline-hints.patch"
  "0006-rfc-kairo-ephemeral-cache-semantics.patch"
  "0007-rfc-kairo-placement-lifetime-hints.patch"
  "0008-rfc-kairo-nvme-zns-fdp-mapping.patch"
  "0009-rfc-kairo-sysfs-debug-counters.patch"
)

foundation_patches=(
  "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"
  "$PATCH_DIR/0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"
)

for patch in "${required_patches[@]}"; do
  if [[ ! -f "$PATCH_DIR/$patch" ]]; then
    echo "[kairo] missing patch: $patch" >&2
    exit 1
  fi
done

for patch in "${foundation_patches[@]}"; do
  if ! grep -q '^diff --git ' "$patch"; then
    echo "[kairo] malformed patch header: $(basename "$patch")" >&2
    exit 1
  fi

  if grep -q '^\+@@' "$patch"; then
    echo "[kairo] malformed hunk marker found in $(basename "$patch")" >&2
    exit 1
  fi
done

if ! grep -Eq 'kairo_is_decode_read|kairo_classify_rq' "$PATCH_DIR/0001-rfc-kairo-mq-deadline-decode-priority.patch"; then
  echo "[kairo] 0001 does not reference shared Kairo classification helpers" >&2
  exit 1
fi

if ! grep -q 'enum kairo_io_class' "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"; then
  echo "[kairo] 0002 does not define enum kairo_io_class" >&2
  exit 1
fi

if ! grep -q 'kairo_decode_dispatches' "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"; then
  echo "[kairo] 0009 does not expose kairo_decode_dispatches" >&2
  exit 1
fi

if [[ -z "$LINUX_TREE" ]]; then
  echo "[kairo] patch metadata checks passed"
  echo "[kairo] tip: pass a Linux 6.8.x source tree to run sequential apply validation"
  exit 0
fi

if [[ ! -d "$LINUX_TREE" ]]; then
  echo "[kairo] Linux source tree not found: $LINUX_TREE" >&2
  exit 1
fi

if [[ ! -f "$LINUX_TREE/block/mq-deadline.c" || ! -f "$LINUX_TREE/block/blk-mq.c" ]]; then
  echo "[kairo] expected block-layer files are missing in $LINUX_TREE" >&2
  exit 1
fi

if [[ ! -f "$LINUX_TREE/include/linux/blk-mq.h" || ! -f "$LINUX_TREE/include/linux/blk_types.h" ]]; then
  echo "[kairo] expected block-layer headers are missing in $LINUX_TREE" >&2
  exit 1
fi

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
  git -C "$scratch_dir" apply --check "$patch"
  git -C "$scratch_dir" apply "$patch"
done

echo "[kairo] patch stack consistency checks passed"
