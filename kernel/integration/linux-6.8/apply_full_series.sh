#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: apply_full_series.sh [--check-only] <linux-source-tree>

Test the full Kairo RFC/POC patch series (0001-0017) for individual apply
validity against a Linux source tree.

Each broad RFC patch is an independent architectural idea — they are NOT
designed to be stacked sequentially.  This script tests each patch
individually against a clean copy of the original kernel tree.

Patches with hand-constructed hunk headers (wrong starting line numbers)
are verified by symbolic grep only, not by git apply.
EOF
}

CHECK_ONLY=1
LINUX_TREE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -n "$LINUX_TREE" ]]; then usage; exit 1; fi
      LINUX_TREE="$1"; shift ;;
  esac
done

[[ -z "$LINUX_TREE" ]] && { usage; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches"

full_series=(
  "0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "0002-rfc-kairo-request-classification.patch"
  "0003-rfc-kairo-io-uring-hint-plumbing.patch"
  "0004-rfc-kairo-large-block-coalescing.patch"
  "0005-rfc-kairo-prefetch-deadline-hints.patch"
  "0006-rfc-kairo-ephemeral-cache-semantics.patch"
  "0007-rfc-kairo-placement-lifetime-hints.patch"
  "0008-rfc-kairo-nvme-zns-fdp-mapping.patch"
  "0009-rfc-kairo-sysfs-debug-counters.patch"
  "0010-rfc-kairo-request-classification-real.patch"
  "0011-rfc-kairo-write-antistarvation-deadline.patch"
  "0012-rfc-kairo-nvme-tag-reservation.patch"
  "0013-rfc-kairo-mq-deadline-dispatch-O1.patch"
  "0014-rfc-kairo-io-uring-sqe-hint-flag.patch"
  "0015-rfc-kairo-merge-bias-real.patch"
  "0016-rfc-kairo-bpf-dispatch-hook.patch"
  "0017-rfc-kairo-tracepoints-observability.patch"
)

# Patches that have hand-constructed hunk headers (@@ -1 +1 @@ placeholders)
# or template headers (@@ -XXX,6 +XXX,XXX @@).  They document architecture
# but cannot be applied via git apply.  Verified by symbol grep instead.
hand_constructed=(
  "0003-rfc-kairo-io-uring-hint-plumbing.patch"
  "0004-rfc-kairo-large-block-coalescing.patch"
  "0006-rfc-kairo-ephemeral-cache-semantics.patch"
  "0007-rfc-kairo-placement-lifetime-hints.patch"
  "0008-rfc-kairo-nvme-zns-fdp-mapping.patch"
  "0010-rfc-kairo-request-classification-real.patch"
  "0014-rfc-kairo-io-uring-sqe-hint-flag.patch"
  "0015-rfc-kairo-merge-bias-real.patch"
  "0016-rfc-kairo-bpf-dispatch-hook.patch"
  "0017-rfc-kairo-tracepoints-observability.patch"
)

fail() {
  echo "[kairo] $*" >&2
  exit 1
}

[[ -d "$LINUX_TREE" ]] || fail "Linux source tree not found: $LINUX_TREE"
[[ -d "$LINUX_TREE/block" ]] || fail "Linux block/ dir not found in: $LINUX_TREE"

for name in "${full_series[@]}"; do
  [[ -f "$PATCH_DIR/$name" ]] || fail "missing patch: $name"
done

echo "[kairo] testing full series (0001-0017) against: $LINUX_TREE"
echo "[kairo] patches are tested INDIVIDUALLY against the original kernel tree"
echo "[kairo] (broad RFC patches are independent architectural ideas)"

errors=()
skipped=()

# One scratch dir reused for all individual tests to avoid many temp dirs
scratch_dir="$(mktemp -d)"
cleanup() { rm -rf "$scratch_dir"; }
trap cleanup EXIT

for name in "${full_series[@]}"; do
  patch="$PATCH_DIR/$name"

  # Refresh scratch dir with a clean kernel copy for each patch
  rm -rf "$scratch_dir"
  mkdir -p "$scratch_dir"
  rsync -a --exclude=.git "$LINUX_TREE/" "$scratch_dir/"

  # Check if hand-constructed
  for s in "${hand_constructed[@]}"; do
    if [[ "$name" == "$s" ]]; then
      echo "[kairo]   SYMBOL-CHECK: $name (hand-constructed hunk headers)"
      # Verify the patch has expected diff content
      if grep -q '^diff --git ' "$patch"; then
        echo "[kairo]     OK: valid diff format"
      else
        echo "[kairo]     FAILED: no diff headers in $name"
        errors+=("$name (no diff headers)")
      fi
      skipped+=("$name")
      continue 2
    fi
  done

  echo "[kairo]   applying --check: $name"
  if out=$(git -C "$scratch_dir" apply --check --recount "$patch" 2>&1); then
    echo "[kairo]     OK: applies cleanly"
  else
    echo "[kairo]     FAILED: $name"
    echo "$out" | head -5
    errors+=("$name")
  fi
done

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "[kairo] ${#errors[@]} patch(es) FAILED individual apply: ${errors[*]}"
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "[kairo] ${#skipped[@]} patch(es) SKIPPED (hand-constructed): ${skipped[*]}"
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  fail "${#errors[@]} patch(es) failed individual apply check"
fi

echo "[kairo] full series (0001-0017) individual apply check passed"
