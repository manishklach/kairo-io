#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: validate_foundation_stack.sh [--check-only] <linux-source-tree>

  --check-only  verify the Linux tree layout and report the git commit if available
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

MQ_DEADLINE_FILE="$LINUX_TREE/block/mq-deadline.c"
BLK_TYPES_FILE="$LINUX_TREE/include/linux/blk_types.h"
BLK_MQ_FILE="$LINUX_TREE/include/linux/blk-mq.h"

if [[ ! -f "$MQ_DEADLINE_FILE" || ! -f "$BLK_TYPES_FILE" || ! -f "$BLK_MQ_FILE" ]]; then
  fail "expected Linux 6.8 foundation files are missing in $LINUX_TREE"
fi

if git -C "$LINUX_TREE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[kairo] Linux tree commit: $(git -C "$LINUX_TREE" rev-parse --short HEAD)"
else
  echo "[kairo] Linux tree is not a git checkout; commit hash unavailable"
fi

if [[ $CHECK_ONLY -eq 1 ]]; then
  echo "[kairo] Linux tree layout checks passed"
  exit 0
fi

blk_types_symbols=(
  "enum kairo_io_class"
  "struct kairo_request_hints"
)

blk_mq_symbols=(
  "kairo_classify_rq"
  "kairo_is_decode_read"
  "kairo_is_prefetch_read"
  "kairo_is_prefill_write"
  "kairo_is_evict"
)

mq_deadline_symbols=(
  "kairo_enable"
  "kairo_decode_budget"
  "kairo_prefetch_budget"
  "kairo_prefetch_deadline_us"
  "kairo_decode_dispatches"
  "kairo_prefetch_dispatches"
  "kairo_prefetch_deadline_hits"
  "kairo_prefetch_budget_skips"
  "kairo_prefill_dispatches"
  "kairo_prefill_demotion_observations"
  "kairo_evict_dispatches"
  "kairo_evict_demotion_observations"
  "kairo_normal_dispatches"
  "kairo_starvation_escapes"
  # Stage 11: tracepoint includes (optional)
  "trace/events/kairo.h"
)

missing=0

for symbol in "${blk_types_symbols[@]}"; do
  if grep -q "$symbol" "$BLK_TYPES_FILE"; then
    echo "[kairo] found blk_types symbol: $symbol"
  else
    echo "[kairo] missing blk_types symbol: $symbol" >&2
    missing=1
  fi
done

for symbol in "${blk_mq_symbols[@]}"; do
  if grep -q "$symbol" "$BLK_MQ_FILE"; then
    echo "[kairo] found blk-mq symbol: $symbol"
  else
    echo "[kairo] missing blk-mq symbol: $symbol" >&2
    missing=1
  fi
done

for symbol in "${mq_deadline_symbols[@]}"; do
  if grep -q "$symbol" "$MQ_DEADLINE_FILE"; then
    echo "[kairo] found mq-deadline symbol: $symbol"
  else
    echo "[kairo] missing mq-deadline symbol: $symbol" >&2
    missing=1
  fi
done

if [[ $missing -ne 0 ]]; then
  fail "foundation stack validation failed"
fi

echo "[kairo] foundation stack validation passed"
