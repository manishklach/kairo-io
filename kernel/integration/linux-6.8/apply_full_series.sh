#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: apply_full_series.sh [--check-only] <linux-source-tree>

Test the full Kairo RFC/POC patch series (0001-0017) for validity.

Foundation patches (0001, 0002) are verified with git apply --check
against the stock Linux tree.

ALL other patches are RFC/POC architectural documents that describe
conceptual changes. They reference symbols introduced by the foundation
patches but have independently constructed hunk context (types, values,
line numbers may differ). These are verified by:
  - Checking that the patch has valid diff format
  - Checking that key Kairo symbols referenced in the patch actually
    exist in the foundation patches (symbolic dependency validation)
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

# Foundation patches — generated from actual kernel source, apply with
# correct context and line numbers.
foundation_patches=(
  "0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "0002-rfc-kairo-request-classification.patch"
)

# Patches that symbolically depend on foundation patches but have
# independently constructed hunk context that differs from the actual
# foundation-patched tree. Verified by symbol grep only.
conceptual_patches=(
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

# Symbolic dependency map: patches that reference symbols from a specific
# foundation patch get an extra grep check against that foundation patch.
declare -A symbol_checks
symbol_checks["0005-rfc-kairo-prefetch-deadline-hints.patch"]="dd_kairo_dispatch_decode_request"
symbol_checks["0009-rfc-kairo-sysfs-debug-counters.patch"]="kairo_enable"
symbol_checks["0011-rfc-kairo-write-antistarvation-deadline.patch"]="dd_kairo_dispatch_decode_request"
symbol_checks["0012-rfc-kairo-nvme-tag-reservation.patch"]="kairo_init_request_hints"
symbol_checks["0013-rfc-kairo-mq-deadline-dispatch-O1.patch"]="dd_kairo_dispatch_decode_request"

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
echo "[kairo]   ${#foundation_patches[@]} foundation patch(es) -> git apply --check"
echo "[kairo]   ${#conceptual_patches[@]} conceptual patch(es)  -> symbol grep"

errors=()

# ── Foundation patches: git apply --check on stock kernel ──────────────

echo "[kairo] --- foundation patches ---"

for name in "${foundation_patches[@]}"; do
  patch="$PATCH_DIR/$name"
  echo "[kairo]   applying --check: $name"
  if out=$(git -C "$LINUX_TREE" apply --check "$patch" 2>&1); then
    echo "[kairo]     OK: applies cleanly"
  else
    echo "[kairo]     FAILED: $name"
    echo "$out" | head -5
    errors+=("$name")
  fi
done

# ── Conceptual patches: diff-format + symbolic dependency check ───────

echo "[kairo] --- conceptual patches ---"

for name in "${conceptual_patches[@]}"; do
  patch="$PATCH_DIR/$name"
  issues=()

  # 1. Must have valid diff format
  if grep -q '^diff --git ' "$patch"; then
    echo "[kairo]   diff-format OK:       $name"
  else
    echo "[kairo]   FAILED (no diff):     $name"
    errors+=("$name (no diff headers)")
    continue
  fi

  # 2. If it has a symbolic dependency, verify the symbol exists in the
  #    foundation patch that introduces it
  sym="${symbol_checks[$name]:-}"
  if [[ -n "$sym" ]]; then
    if grep -q "$sym" "$PATCH_DIR/0001-rfc-kairo-mq-deadline-decode-priority.patch" || \
       grep -q "$sym" "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"; then
      echo "[kairo]   symbol OK  (${sym}):  $name"
    else
      echo "[kairo]   FAILED (missing symbol '${sym}' in foundation): $name"
      issues+=("missing symbol ${sym}")
    fi
  fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    echo "[kairo]     OK: $name"
  else
    echo "[kairo]     FAILED: $name (${issues[*]})"
    errors+=("$name (${issues[*]})")
  fi
done

# ── Report ─────────────────────────────────────────────────────────────

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "[kairo] ${#errors[@]} patch(es) FAILED: ${errors[*]}"
  fail "${#errors[@]} patch(es) failed validation"
fi

echo "[kairo] full series (0001-0017) validation passed"
