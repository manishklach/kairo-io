#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <linux-source-tree>" >&2
  exit 1
fi

LINUX_TREE="$1"

if [[ ! -d "$LINUX_TREE" ]]; then
  echo "[kairo] Linux source tree not found: $LINUX_TREE" >&2
  exit 1
fi

if [[ ! -f "$LINUX_TREE/Makefile" ]]; then
  echo "[kairo] kernel Makefile not found in: $LINUX_TREE" >&2
  exit 1
fi

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"

echo "[kairo] running make olddefconfig"
if ! make -C "$LINUX_TREE" olddefconfig; then
  echo "[kairo] make olddefconfig failed" >&2
  echo "[kairo] local fallback: make -C \"$LINUX_TREE\" olddefconfig" >&2
  exit 1
fi

echo "[kairo] attempting focused build: block/blk-mq.o block/mq-deadline.o"
if make -C "$LINUX_TREE" -j"$JOBS" block/blk-mq.o block/mq-deadline.o; then
  echo "[kairo] focused block object build completed"
  exit 0
fi

echo "[kairo] focused build failed" >&2
echo "[kairo] local fallback 1: make -C \"$LINUX_TREE\" -j\"$JOBS\" block/mq-deadline.o" >&2
echo "[kairo] local fallback 2: make -C \"$LINUX_TREE\" M=block block/blk-mq.o block/mq-deadline.o" >&2
echo "[kairo] if the Linux tree still rejects direct object targets, use the tree's local block build flow and record it in patch_apply_notes.md" >&2
exit 1
