#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-source-tree>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
PATCH_PATH="$REPO_ROOT/kernel/patches/0001-rfc-kairo-mq-deadline-decode-priority.patch"
LINUX_TREE="$1"

if [[ ! -d "$LINUX_TREE" ]]; then
  echo "[kairo] Linux source tree not found: $LINUX_TREE" >&2
  exit 1
fi

if [[ ! -f "$LINUX_TREE/block/mq-deadline.c" ]]; then
  echo "[kairo] expected file missing: $LINUX_TREE/block/mq-deadline.c" >&2
  exit 1
fi

if [[ ! -f "$PATCH_PATH" ]]; then
  echo "[kairo] patch not found: $PATCH_PATH" >&2
  exit 1
fi

echo "[kairo] checking patch applicability against $LINUX_TREE"
if git -C "$LINUX_TREE" apply --check "$PATCH_PATH"; then
  echo "[kairo] patch check passed"
else
  echo "[kairo] patch check failed" >&2
  exit 1
fi

echo "[kairo] applying patch"
if git -C "$LINUX_TREE" apply "$PATCH_PATH"; then
  echo "[kairo] patch applied successfully"
else
  echo "[kairo] patch apply failed" >&2
  exit 1
fi
