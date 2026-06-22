#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: build_foundation_objects.sh [--check-only] <linux-source-tree>

  --check-only  verify the tree layout, report the git commit if available, and print the build commands
EOF
}

CHECK_ONLY=0
LINUX_TREE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=1
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

fail() {
  echo "[kairo] $*" >&2
  exit 1
}

if [[ ! -d "$LINUX_TREE" ]]; then
  fail "Linux source tree not found: $LINUX_TREE"
fi

if [[ ! -f "$LINUX_TREE/Makefile" ]]; then
  fail "kernel Makefile not found in: $LINUX_TREE"
fi

if git -C "$LINUX_TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[kairo] Linux tree commit: $(git -C "$LINUX_TREE" rev-parse --short HEAD)"
else
  echo "[kairo] Linux tree is not a git checkout; commit hash unavailable"
fi

JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 1)"

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "[kairo] check-only mode"
  echo "[kairo] build command 1: make -C \"$LINUX_TREE\" olddefconfig"
  echo "[kairo] build command 2: make -C \"$LINUX_TREE\" -j\"$JOBS\" block/blk-mq.o block/mq-deadline.o"
  echo "[kairo] fallback 1: make -C \"$LINUX_TREE\" -j\"$JOBS\" block/mq-deadline.o"
  echo "[kairo] fallback 2: make -C \"$LINUX_TREE\" M=block block/blk-mq.o block/mq-deadline.o"
  exit 0
fi

echo "[kairo] running make olddefconfig"
if ! make -C "$LINUX_TREE" olddefconfig; then
  fail "make olddefconfig failed; retry locally with: make -C \"$LINUX_TREE\" olddefconfig"
fi

echo "[kairo] attempting focused build: block/blk-mq.o block/mq-deadline.o"
if make -C "$LINUX_TREE" -j"$JOBS" block/blk-mq.o block/mq-deadline.o; then
  echo "[kairo] focused block object build completed"
  exit 0
fi

echo "[kairo] focused build failed" >&2
echo "[kairo] local fallback 1: make -C \"$LINUX_TREE\" -j\"$JOBS\" block/mq-deadline.o" >&2
echo "[kairo] local fallback 2: make -C \"$LINUX_TREE\" M=block block/blk-mq.o block/mq-deadline.o" >&2
echo "[kairo] if the Linux tree still rejects direct object targets, record the exact failure in patch_apply_notes.md" >&2
exit 1
