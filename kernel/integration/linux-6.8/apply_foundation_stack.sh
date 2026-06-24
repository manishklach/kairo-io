#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: apply_foundation_stack.sh [--check-only] [--force] [--with-tracepoints] <linux-source-tree>

  --check-only         verify that the foundation patches apply cleanly
  --force              allow apply on a Linux git tree with uncommitted changes
  --with-tracepoints   also apply foundation tracepoint patch (0005)
EOF
}

CHECK_ONLY=0
FORCE=0
WITH_TRACEPOINTS=0
LINUX_TREE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --with-tracepoints)
      WITH_TRACEPOINTS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -n "$LINUX_TREE" ]]; then
        usage
        exit 1
      fi
      LINUX_TREE="$1"
      shift
      ;;
  esac
done

if [[ -z "$LINUX_TREE" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches/foundation"

foundation_patches=(
  "$PATCH_DIR/0001-kairo-request-classification.patch"
  "$PATCH_DIR/0002-kairo-mq-deadline-decode-priority.patch"
  "$PATCH_DIR/0003-kairo-prefetch-prefill-evict-policy.patch"
  "$PATCH_DIR/0004-kairo-mq-deadline-sysfs-counters.patch"
  "$PATCH_DIR/0005-kairo-foundation-tracepoints.patch"
)

required_files=(
  "$LINUX_TREE/block/mq-deadline.c"
  "$LINUX_TREE/block/blk-mq.c"
  "$LINUX_TREE/include/linux/blk-mq.h"
  "$LINUX_TREE/include/linux/blk_types.h"
)

fail() {
  echo "[kairo] $*" >&2
  exit 1
}

if [[ ! -d "$LINUX_TREE" ]]; then
  fail "Linux source tree not found: $LINUX_TREE"
fi

for file in "${required_files[@]}"; do
  [[ -f "$file" ]] || fail "required Linux file missing: $file"
done

for patch in "${foundation_patches[@]}"; do
  [[ -f "$patch" ]] || fail "missing foundation patch: $patch"
done

if ! git -C "$LINUX_TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "apply requires a Linux git checkout: $LINUX_TREE"
fi

linux_head="$(git -C "$LINUX_TREE" rev-parse --short HEAD 2>/dev/null || true)"
if [[ -n "$linux_head" ]]; then
  echo "[kairo] Linux tree commit: $linux_head"
fi

dirty_status="$(git -C "$LINUX_TREE" status --short --untracked-files=no 2>/dev/null || true)"
if [[ -n "$dirty_status" && $FORCE -ne 1 ]]; then
  fail "Linux tree has uncommitted changes; re-run with --force after reviewing them"
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

echo "[kairo] checking foundation stack against: $LINUX_TREE"
for patch in "${foundation_patches[@]}"; do
  # Skip tracepoint patch unless --with-tracepoints
  if [[ "$(basename "$patch")" == "0005-kairo-foundation-tracepoints.patch" && \
        $WITH_TRACEPOINTS -ne 1 ]]; then
    echo "[kairo] skipping tracepoint patch 0005 (use --with-tracepoints to include)"
    continue
  fi
  echo "[kairo] git apply --check $(basename "$patch")"
  if ! git -C "$scratch_dir" apply --check --recount "$patch"; then
    fail "apply check failed for $(basename "$patch"); inspect the Linux tree version and patch context"
  fi

  git -C "$scratch_dir" apply --recount "$patch"
done

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "[kairo] foundation stack apply check passed"
  exit 0
fi

echo "[kairo] all checks passed; applying foundation stack"
for patch in "${foundation_patches[@]}"; do
  if [[ "$(basename "$patch")" == "0005-kairo-foundation-tracepoints.patch" && \
        $WITH_TRACEPOINTS -ne 1 ]]; then
    continue
  fi
  echo "[kairo] applying $(basename "$patch")"
  if ! git -C "$LINUX_TREE" apply --recount "$patch"; then
    fail "failed to apply $(basename "$patch"); the Linux tree may no longer match the checked context"
  fi
done

echo "[kairo] foundation stack applied successfully"

if [[ $WITH_TRACEPOINTS -eq 1 ]]; then
  echo "[kairo] foundation tracepoints (0005) included"
fi
