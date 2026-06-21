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

if ! grep -q 'kairo_classify_rq' "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"; then
  echo "[kairo] 0002 does not define kairo_classify_rq" >&2
  exit 1
fi

if ! grep -Eq 'rq->kairo_hints\.io_class|explicit Kairo hints' "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"; then
  echo "[kairo] 0002 does not prioritize explicit Kairo hints before ioprio fallback" >&2
  exit 1
fi

if ! grep -q 'RWF_KAIRO_DECODE' "$PATCH_DIR/0003-rfc-kairo-io-uring-hint-plumbing.patch"; then
  echo "[kairo] 0003 does not define RWF_KAIRO_DECODE" >&2
  exit 1
fi

if ! grep -q 'IOCB_KAIRO_DECODE' "$PATCH_DIR/0003-rfc-kairo-io-uring-hint-plumbing.patch"; then
  echo "[kairo] 0003 does not define IOCB_KAIRO_DECODE" >&2
  exit 1
fi

if ! grep -q 'kiocb_set_kairo_flags' "$PATCH_DIR/0003-rfc-kairo-io-uring-hint-plumbing.patch"; then
  echo "[kairo] 0003 does not define kiocb_set_kairo_flags" >&2
  exit 1
fi

if ! grep -q 'KAIRO_HINT_EPHEMERAL' "$PATCH_DIR/0006-rfc-kairo-ephemeral-cache-semantics.patch"; then
  echo "[kairo] 0006 does not define KAIRO_HINT_EPHEMERAL" >&2
  exit 1
fi

if ! grep -q 'KAIRO_HINT_RECOMPUTABLE' "$PATCH_DIR/0006-rfc-kairo-ephemeral-cache-semantics.patch"; then
  echo "[kairo] 0006 does not define KAIRO_HINT_RECOMPUTABLE" >&2
  exit 1
fi

if ! grep -q 'kairo_is_ephemeral' "$PATCH_DIR/0006-rfc-kairo-ephemeral-cache-semantics.patch"; then
  echo "[kairo] 0006 does not define kairo_is_ephemeral" >&2
  exit 1
fi

if ! grep -q 'kairo_is_recomputable' "$PATCH_DIR/0006-rfc-kairo-ephemeral-cache-semantics.patch"; then
  echo "[kairo] 0006 does not define kairo_is_recomputable" >&2
  exit 1
fi

if ! grep -q -- '--hint-mode' "$REPO_ROOT/bench/kairo_bench.c"; then
  echo "[kairo] benchmark does not support --hint-mode" >&2
  exit 1
fi

if ! grep -q 'KAIRO_RWF_EPHEMERAL' "$REPO_ROOT/include/kairo_hints.h"; then
  echo "[kairo] include/kairo_hints.h does not define KAIRO_RWF_EPHEMERAL" >&2
  exit 1
fi

if ! grep -q -- '--semantic-mode' "$REPO_ROOT/bench/kairo_bench.c"; then
  echo "[kairo] benchmark does not support --semantic-mode" >&2
  exit 1
fi

if ! grep -q 'kairo_decode_dispatches' "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"; then
  echo "[kairo] 0009 does not expose kairo_decode_dispatches" >&2
  exit 1
fi

if ! grep -q 'kairo_ioprio_hinted_requests' "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"; then
  echo "[kairo] 0009 does not reference kairo_ioprio_hinted_requests" >&2
  exit 1
fi

if ! grep -q 'kairo_rwf_hinted_requests' "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"; then
  echo "[kairo] 0009 does not reference kairo_rwf_hinted_requests" >&2
  exit 1
fi

if ! grep -q 'kairo_ephemeral_requests' "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"; then
  echo "[kairo] 0009 does not reference kairo_ephemeral_requests" >&2
  exit 1
fi

if ! grep -q 'kairo_recomputable_requests' "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"; then
  echo "[kairo] 0009 does not reference kairo_recomputable_requests" >&2
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
