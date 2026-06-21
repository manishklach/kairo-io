#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches"
FOUNDATION_DIR="$PATCH_DIR/foundation"
LINUX_TREE="${1:-}"

required_broad_patches=(
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

required_foundation_patches=(
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch"
  "$FOUNDATION_DIR/0002-kairo-mq-deadline-decode-priority.patch"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch"
)

for patch in "${required_broad_patches[@]}"; do
  if [[ ! -f "$PATCH_DIR/$patch" ]]; then
    echo "[kairo] missing broad RFC/POC patch: $patch" >&2
    exit 1
  fi
done

for patch in "${required_foundation_patches[@]}"; do
  if [[ ! -f "$patch" ]]; then
    echo "[kairo] missing foundation patch: $(basename "$patch")" >&2
    exit 1
  fi

  if ! grep -q '^diff --git ' "$patch"; then
    echo "[kairo] malformed patch header: $(basename "$patch")" >&2
    exit 1
  fi

  if grep -q '^\+@@' "$patch"; then
    echo "[kairo] malformed hunk marker found in $(basename "$patch")" >&2
    exit 1
  fi
done

foundation_symbols=(
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:enum kairo_io_class"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:struct kairo_request_hints"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_classify_rq"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_decode_read"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_prefetch_read"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_prefill_write"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_evict"
  "$FOUNDATION_DIR/0002-kairo-mq-deadline-decode-priority.patch:kairo_enable"
  "$FOUNDATION_DIR/0002-kairo-mq-deadline-decode-priority.patch:kairo_decode_budget"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_budget"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_deadline_us"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_dispatches"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefill_dispatches"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_evict_dispatches"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_prefetch_deadline_hits"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_prefetch_budget_skips"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_prefill_demotions"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_evict_demotions"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_normal_dispatches"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_starvation_escapes"
)

for entry in "${foundation_symbols[@]}"; do
  patch="${entry%%:*}"
  symbol="${entry#*:}"
  if ! grep -q "$symbol" "$patch"; then
    echo "[kairo] missing symbol $symbol in $(basename "$patch")" >&2
    exit 1
  fi
done

if [[ -z "$LINUX_TREE" ]]; then
  echo "[kairo] patch metadata checks passed"
  echo "[kairo] tip: pass a Linux 6.8.x source tree to run foundation apply checks"
  exit 0
fi

if [[ ! -d "$LINUX_TREE" ]]; then
  echo "[kairo] Linux source tree not found: $LINUX_TREE" >&2
  exit 1
fi

required_linux_files=(
  "$LINUX_TREE/block/mq-deadline.c"
  "$LINUX_TREE/block/blk-mq.c"
  "$LINUX_TREE/include/linux/blk-mq.h"
  "$LINUX_TREE/include/linux/blk_types.h"
)

for file in "${required_linux_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "[kairo] expected Linux file missing: $file" >&2
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

for patch in "${required_foundation_patches[@]}"; do
  echo "[kairo] checking patch applicability: $(basename "$patch")"
  git -C "$scratch_dir" apply --check "$patch"
  git -C "$scratch_dir" apply "$patch"
done

echo "[kairo] foundation patch applicability checks passed"
