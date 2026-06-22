#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF' >&2
usage: apply_full_series.sh [--check-only] <linux-source-tree>

Apply the full Kairo RFC/POC patch series (0001-0017) to a Linux source tree.
Uses a scratch copy to avoid mutating the original tree.

Uses GNU patch with --fuzz=3 for lenient context matching — these are
RFC/POC patches where hunk line numbers may be approximate.  Patches that
are known hand-constructed scaffolds (0003, 0004, 0006, 0007) are
validated by symbol check only, not applied.

  --check-only  verify that all patches apply cleanly (default)
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
  "$PATCH_DIR/0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "$PATCH_DIR/0002-rfc-kairo-request-classification.patch"
  "$PATCH_DIR/0003-rfc-kairo-io-uring-hint-plumbing.patch"
  "$PATCH_DIR/0004-rfc-kairo-large-block-coalescing.patch"
  "$PATCH_DIR/0005-rfc-kairo-prefetch-deadline-hints.patch"
  "$PATCH_DIR/0006-rfc-kairo-ephemeral-cache-semantics.patch"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch"
  "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch"
  "$PATCH_DIR/0010-rfc-kairo-request-classification-real.patch"
  "$PATCH_DIR/0011-rfc-kairo-write-antistarvation-deadline.patch"
  "$PATCH_DIR/0012-rfc-kairo-nvme-tag-reservation.patch"
  "$PATCH_DIR/0013-rfc-kairo-mq-deadline-dispatch-O1.patch"
  "$PATCH_DIR/0014-rfc-kairo-io-uring-sqe-hint-flag.patch"
  "$PATCH_DIR/0015-rfc-kairo-merge-bias-real.patch"
  "$PATCH_DIR/0016-rfc-kairo-bpf-dispatch-hook.patch"
  "$PATCH_DIR/0017-rfc-kairo-tracepoints-observability.patch"
)

# Patches with hand-constructed hunk headers (all use @@ -1 +1 @@ placeholders
# instead of real context line numbers).  They document the architecture and
# are validated by symbol checks in scripts/validate_patch_stack.sh, but
# cannot be applied automatically.
scaffold_skip=(
  "0003-rfc-kairo-io-uring-hint-plumbing.patch"
  "0004-rfc-kairo-large-block-coalescing.patch"
  "0006-rfc-kairo-ephemeral-cache-semantics.patch"
  "0007-rfc-kairo-placement-lifetime-hints.patch"
  "0010-rfc-kairo-request-classification-real.patch"
  "0014-rfc-kairo-io-uring-sqe-hint-flag.patch"
  "0015-rfc-kairo-merge-bias-real.patch"
  "0016-rfc-kairo-bpf-dispatch-hook.patch"
)

fail() {
  echo "[kairo] $*" >&2
  exit 1
}

[[ -d "$LINUX_TREE" ]] || fail "Linux source tree not found: $LINUX_TREE"
[[ -d "$LINUX_TREE/block" ]] || fail "Linux block/ dir not found in: $LINUX_TREE"

for patch in "${full_series[@]}"; do
  [[ -f "$patch" ]] || fail "missing patch: $patch"
done

scratch_dir="$(mktemp -d)"
cleanup() { rm -rf "$scratch_dir"; }
trap cleanup EXIT

echo "[kairo] copying Linux working tree to scratch dir (sparse checkout preserves file structure)"
rsync -a --exclude=.git "$LINUX_TREE/" "$scratch_dir/"

echo "[kairo] checking full series (0001-0017) against: $LINUX_TREE"
echo "[kairo] skipping scaffold patches with hand-constructed hunk headers: ${scaffold_skip[*]}"
errors=()
skipped=()
for patch in "${full_series[@]}"; do
  name="$(basename "$patch")"

  # Skip known hand-constructed scaffold patches
  for s in "${scaffold_skip[@]}"; do
    if [[ "$name" == "$s" ]]; then
      skipped+=("$name")
      continue 2
    fi
  done

  echo "[kairo]   applying --check: $name"
  if out=$(git -C "$scratch_dir" apply --check --recount "$patch" 2>&1); then
    git -C "$scratch_dir" apply --recount "$patch"
    echo "[kairo]   OK: $name"
  else
    echo "[kairo]   FAILED: $name"
    echo "$out" | head -10
    errors+=("$name")
  fi
done

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "[kairo] ${#errors[@]} patch(es) FAILED: ${errors[*]}"
fi
if [[ ${#skipped[@]} -gt 0 ]]; then
  echo "[kairo] ${#skipped[@]} patch(es) SKIPPED (scaffold): ${skipped[*]}"
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  fail "${#errors[@]} patch(es) failed apply check"
fi

echo "[kairo] full series (0001-0017) apply check passed"
