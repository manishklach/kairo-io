#!/usr/bin/env bash
#
# validate_foundation_tracepoints.sh
#
# Checks a patched Linux 6.8 tree for foundation tracepoint presence.
# Does not require boot, root, or a running kernel.
#
# Usage:
#   ./validate_foundation_tracepoints.sh <patched-linux-source-tree>
#
# Returns 0 if all tracepoints are present, 1 otherwise.

set -euo pipefail

LINUX_TREE="${1:-}"

if [[ -z "$LINUX_TREE" ]]; then
  echo "Usage: $0 <patched-linux-source-tree>" >&2
  exit 1
fi

fail() {
  echo "[kairo] FAIL: $*" >&2
  exit 1
}

ok() {
  echo "[kairo] OK: $*"
}

TRACE_HEADER="$LINUX_TREE/include/trace/events/kairo.h"
BLK_MQ_C="$LINUX_TREE/block/blk-mq.c"
MQ_DEADLINE_C="$LINUX_TREE/block/mq-deadline.c"

# Check header exists
if [[ ! -f "$TRACE_HEADER" ]]; then
  fail "include/trace/events/kairo.h not found in $LINUX_TREE"
fi
ok "include/trace/events/kairo.h exists"

# Check TRACE_SYSTEM
grep -q 'TRACE_SYSTEM[[:space:]]*kairo' "$TRACE_HEADER" || \
  fail "TRACE_SYSTEM kairo not found in kairo.h"
ok "TRACE_SYSTEM kairo"

# Check TRACE_EVENT definitions
for tp in \
  "kairo_request_classified" \
  "kairo_decode_dispatch" \
  "kairo_prefetch_dispatch" \
  "kairo_write_demoted"; do
  grep -q "TRACE_EVENT($tp" "$TRACE_HEADER" || \
    fail "TRACE_EVENT($tp) not found in kairo.h"
  ok "TRACE_EVENT($tp) present"
done

# Check include in blk-mq.c
grep -q '#include <trace/events/kairo.h>' "$BLK_MQ_C" || \
  fail "#include <trace/events/kairo.h> not found in blk-mq.c"
ok "blk-mq.c includes trace/events/kairo.h"

# Check include in mq-deadline.c
grep -q '#include <trace/events/kairo.h>' "$MQ_DEADLINE_C" || \
  fail "#include <trace/events/kairo.h> not found in mq-deadline.c"
ok "mq-deadline.c includes trace/events/kairo.h"

# Check LINUX-6.8-CHECK annotations
grep -q "LINUX-6.8-CHECK" "$BLK_MQ_C" || \
  fail "LINUX-6.8-CHECK annotation not found in blk-mq.c"
ok "blk-mq.c has LINUX-6.8-CHECK annotations"

grep -q "LINUX-6.8-CHECK" "$MQ_DEADLINE_C" || \
  fail "LINUX-6.8-CHECK annotation not found in mq-deadline.c"
ok "mq-deadline.c has LINUX-6.8-CHECK annotations"

echo ""
echo "[kairo] All foundation tracepoint checks passed."
