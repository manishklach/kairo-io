#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: smoke_foundation_stack.sh [--check-only] [--build|--skip-build] <linux-source-tree>

  --check-only  run non-mutating checks only (default behavior)
  --build       run the foundation object build after validation
  --skip-build  skip the build step explicitly
EOF
}

CHECK_ONLY=1
RUN_BUILD=0
LINUX_TREE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=1
      shift
      ;;
    --build)
      RUN_BUILD=1
      shift
      ;;
    --skip-build)
      RUN_BUILD=0
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

echo "[kairo] step 1: validate foundation patch metadata and apply checks"
"$REPO_ROOT/scripts/validate_patch_stack.sh"

echo "[kairo] step 2: check whether the foundation symbols are already present"
if "$SCRIPT_DIR/validate_foundation_stack.sh" "$LINUX_TREE"; then
  echo "[kairo] foundation symbols are already present in the Linux tree"
elif grep -q 'kairo_' "$LINUX_TREE/block/mq-deadline.c" \
  || grep -q 'kairo_' "$LINUX_TREE/include/linux/blk-mq.h" \
  || grep -q 'kairo_' "$LINUX_TREE/include/linux/blk_types.h"; then
  echo "[kairo] Linux tree appears to contain an older or partial Kairo patch set" >&2
  echo "[kairo] use a clean Linux checkout for apply checks, or refresh the local tree to the current foundation stack" >&2
  exit 1
else
  echo "[kairo] foundation symbols are not present yet; running clean-tree apply checks"
  "$REPO_ROOT/scripts/validate_patch_stack.sh" "$LINUX_TREE"
  "$SCRIPT_DIR/apply_foundation_stack.sh" --check-only "$LINUX_TREE"
fi

if [[ $RUN_BUILD -eq 1 ]]; then
  echo "[kairo] step 3: build foundation objects"
  "$SCRIPT_DIR/build_foundation_objects.sh" "$LINUX_TREE"
else
  echo "[kairo] step 3: build skipped"
fi
