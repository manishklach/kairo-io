#!/usr/bin/env bash
# Stage 7.5: Audit NVMe hook points in a real Linux 6.8 tree.
#
# For each hook point that the Kairo 0008 patch touches, this script
# checks whether the candidate real kernel symbols exist in the stock
# tree and whether the Kairo-added symbols are absent (confirming that
# the hooks are Kairo-only additions).
#
# Usage:
#   ./audit_nvme_hooks.sh [linux-6.8-source-tree]
#
# If no tree path is given, the script searches a few common locations.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LINUX_TREE="${1:-}"

if [[ -z "$LINUX_TREE" ]]; then
  for candidate in \
    /usr/src/linux \
    /home/build/linux-6.8 \
    /tmp/linux-6.8 \
    /tmp/linux-6.8.12 \
    ../linux-6.8; do
    if [[ -d "$candidate" ]]; then
      LINUX_TREE="$candidate"
      break
    fi
  done
fi

if [[ -z "$LINUX_TREE" || ! -d "$LINUX_TREE" ]]; then
  echo "Usage: $0 <linux-6.8-source-tree>"
  echo ""
  echo "No Linux 6.8 source tree found. Provide one explicitly or"
  echo "extract a tarball to a known location first."
  exit 1
fi

echo "[audit] Linux tree: $LINUX_TREE"
echo ""

failed=0
pass_count=0
fail_count=0

check_symbol_present() {
  local file="$1" symbol="$2" label="$3"
  local full_path="$LINUX_TREE/$file"
  if [[ ! -f "$full_path" ]]; then
    echo "  FAIL   $label: file not found: $file"
    ((fail_count++)) || true
    return
  fi
  if grep -q "$symbol" "$full_path"; then
    echo "  OK     $label"
    ((pass_count++)) || true
  else
    echo "  FAIL   $label: symbol '$symbol' not found in $file"
    ((fail_count++)) || true
  fi
}

check_symbol_absent() {
  local file="$1" symbol="$2" label="$3"
  local full_path="$LINUX_TREE/$file"
  if [[ ! -f "$full_path" ]]; then
    echo "  FAIL   $label: file not found: $file"
    ((fail_count++)) || true
    return
  fi
  if grep -q "$symbol" "$full_path" 2>/dev/null; then
    echo "  WARN   $label: Kairo symbol '$symbol' unexpectedly FOUND in stock tree"
    ((fail_count++)) || true
  else
    echo "  OK     $label (absent as expected)"
    ((pass_count++)) || true
  fi
}

echo "--- Candidate real kernel symbols (should be present) ---"

check_symbol_present "include/linux/blk_types.h" "struct request" "blk_types: struct request"
check_symbol_present "include/linux/blk_types.h" "enum req_opf" "blk_types: enum req_opf"
check_symbol_present "include/linux/blk_types.h" "struct bio" "blk_types: struct bio"

check_symbol_present "include/linux/blk-mq.h" "struct request_queue" "blk-mq: struct request_queue"
check_symbol_present "include/linux/blk-mq.h" "blk_mq_rq_to_pdu" "blk-mq: blk_mq_rq_to_pdu"
check_symbol_present "include/linux/blk-mq.h" "blk_mq_unique_tag" "blk-mq: blk_mq_unique_tag"

check_symbol_present "include/linux/nvme.h" "struct nvme_command" "nvme.h: struct nvme_command"
check_symbol_present "include/linux/nvme.h" "struct nvme_id_ctrl" "nvme.h: struct nvme_id_ctrl"
check_symbol_present "include/linux/nvme.h" "enum nvme_opcode" "nvme.h: enum nvme_opcode"

check_symbol_present "drivers/nvme/host/nvme.h" "struct nvme_ctrl" "host/nvme.h: struct nvme_ctrl"
check_symbol_present "drivers/nvme/host/nvme.h" "struct nvme_ns" "host/nvme.h: struct nvme_ns"
check_symbol_present "drivers/nvme/host/nvme.h" "nvme_alloc_request" "host/nvme.h: nvme_alloc_request"

check_symbol_present "drivers/nvme/host/core.c" "nvme_setup_cmd" "core.c: nvme_setup_cmd"
check_symbol_present "drivers/nvme/host/core.c" "nvme_setup_rw" "core.c: nvme_setup_rw"
check_symbol_present "drivers/nvme/host/core.c" "nr_streams" "core.c: nr_streams field"

check_symbol_present "drivers/nvme/host/zns.c" "nvme_setup_zone_append" "zns.c: nvme_setup_zone_append"
check_symbol_present "drivers/nvme/host/zns.c" "nvme_zone_mgmt" "zns.c: nvme_zone_mgmt"
check_symbol_present "drivers/nvme/host/zns.c" "nvme_zns_fill_zone_info" "zns.c: nvme_zns_fill_zone_info"

echo ""
echo "--- Kairo symbols (should be absent from stock tree) ---"

check_symbol_absent "include/linux/blk_types.h" "kairo_backend_class" "blk_types: kairo_backend_class absent"
check_symbol_absent "include/linux/blk_types.h" "kairo_backend_hint" "blk_types: kairo_backend_hint absent"
check_symbol_absent "include/linux/blk_types.h" "kairo_backend_caps" "blk_types: kairo_backend_caps absent"
check_symbol_absent "include/linux/blk_types.h" "KAIRO_BACKEND_" "blk_types: KAIRO_BACKEND_* flags absent"
check_symbol_absent "include/linux/blk-mq.h" "kairo_backend_hint_apply_caps" "blk-mq: kairo_backend_hint_apply_caps absent"
check_symbol_absent "include/linux/nvme.h" "nvme_kairo_mapping" "nvme.h: nvme_kairo_mapping absent"
check_symbol_absent "drivers/nvme/host/nvme.h" "nvme_kairo_get_backend_caps" "host/nvme.h: nvme_kairo_get_backend_caps absent"
check_symbol_absent "drivers/nvme/host/nvme.h" "kairo_backend_caps" "host/nvme.h: kairo_backend_caps absent"

echo ""
echo "--- Summary ---"
echo "  Passed: $pass_count"
echo "  Failed: $fail_count"

if (( fail_count > 0 )); then
  echo ""
  echo "WARNING: Some checks failed. Review the FAIL/WARN lines above."
  echo "  - FAIL on a candidate symbol means the Linux 6.8 tree may be"
  echo "    incomplete or a different version."
  echo "  - WARN on a Kairo symbol means the tree was already patched"
  echo "    or contains stray Kairo symbols."
  exit 1
fi

echo "  All checks passed. The tree is a clean Linux 6.8 baseline."
exit 0
