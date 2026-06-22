#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$REPO_ROOT/kernel/patches"
FOUNDATION_DIR="$PATCH_DIR/foundation"
LINUX_TREE="${1:-}"

fail() {
  echo "[kairo] $*" >&2
  exit 1
}

required_broad_patches=(
  "0001-rfc-kairo-mq-deadline-decode-priority.patch"
  "0002-rfc-kairo-request-classification.patch"
  "0003-rfc-kairo-io-uring-hint-plumbing.patch"
  "0004-rfc-kairo-large-block-coalescing.patch"
  "0005-rfc-kairo-prefetch-deadline-hints.patch"
  "0006-rfc-kairo-ephemeral-cache-semantics.patch"
  "0007-rfc-kairo-placement-lifetime-hints.patch"
  "0008-rfc-kairo-nvme-zns-fdp-mapping.patch"
  "0009-rfc-kairo-sysfs-debug-counters.patch"
)

required_foundation_patches=(
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch"
  "$FOUNDATION_DIR/0002-kairo-mq-deadline-decode-priority.patch"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch"
)

required_support_files=(
  "$FOUNDATION_DIR/README.md"
  "$REPO_ROOT/docs/kernel_foundation_stack.md"
  "$REPO_ROOT/docs/kernel_foundation_invariants.md"
  "$REPO_ROOT/kernel/integration/linux-6.8/apply_foundation_stack.sh"
  "$REPO_ROOT/kernel/integration/linux-6.8/validate_foundation_stack.sh"
  "$REPO_ROOT/kernel/integration/linux-6.8/build_foundation_objects.sh"
  "$REPO_ROOT/kernel/integration/linux-6.8/smoke_foundation_stack.sh"
)

for patch in "${required_broad_patches[@]}"; do
  [[ -f "$PATCH_DIR/$patch" ]] || fail "missing broad RFC/POC patch: $patch"
done

for path in "${required_support_files[@]}"; do
  [[ -f "$path" ]] || fail "missing foundation support file: $path"
done

for patch in "${required_foundation_patches[@]}"; do
  [[ -f "$patch" ]] || fail "missing foundation patch: $(basename "$patch")"

  if ! grep -q '^diff --git ' "$patch"; then
    fail "malformed patch header: $(basename "$patch")"
  fi

  if grep -q '^\+@@' "$patch"; then
    fail "malformed hunk marker found in $(basename "$patch")"
  fi
done

if grep -RInE '(/C:/|C:\\\\)' \
  "$REPO_ROOT/docs" \
  "$REPO_ROOT/kernel/integration/linux-6.8" \
  "$REPO_ROOT/README.md" >/dev/null; then
  fail "local absolute paths found in repository documentation"
fi

if grep -A2 -F 'Next, dispatch requests in priority order.' \
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch" | \
  grep -q 'for (prio = DD_BE_PRIO; prio <= DD_PRIO_MAX; prio++)'; then
  fail "foundation patch 0003 skips ordinary RT priority in the normal mq-deadline loop"
fi

foundation_symbols=(
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:enum kairo_io_class"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:struct kairo_request_hints"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_classify_rq"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_decode_read"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_prefetch_read"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_prefill_write"
  "$FOUNDATION_DIR/0001-kairo-request-classification.patch:kairo_is_evict"
  "$FOUNDATION_DIR/0002-kairo-mq-deadline-decode-priority.patch:kairo_enable"
  "$FOUNDATION_DIR/0002-kairo-mq-deadline-decode-priority.patch:kairo_decode_budget"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_budget"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_deadline_us"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_dispatches"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_deadline_hits"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefetch_budget_skips"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefill_dispatches"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_prefill_demotion_observations"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_evict_dispatches"
  "$FOUNDATION_DIR/0003-kairo-prefetch-prefill-evict-policy.patch:kairo_evict_demotion_observations"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_normal_dispatches"
  "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch:kairo_starvation_escapes"
)

for entry in "${foundation_symbols[@]}"; do
  patch="${entry%%:*}"
  symbol="${entry#*:}"
  grep -q "$symbol" "$patch" || fail "missing symbol $symbol in $(basename "$patch")"
done

# Stage 6.5: verify experiment harness
stage65_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 6.5: missing pattern '$pattern' in $(basename "$file")"
}

stage65_file_exists() {
  [[ -f "$1" ]] || fail "Stage 6.5: missing file: $1"
}

RSE="$SCRIPT_DIR/run_stage6_placement_experiment.sh"
PSP="$SCRIPT_DIR/parse_stage6_placement_summary.py"
KB="$REPO_ROOT/bench/kairo_bench.c"
DOC="$REPO_ROOT/docs/stage6_model_session_lifetime.md"

stage65_has_pattern "$RSE" "results/stage6"
stage65_has_pattern "$RSE" "block-device"
stage65_has_pattern "$RSE" "collect_kairo_counters.sh"
stage65_file_exists "$PSP"
stage65_has_pattern "$PSP" "--csv"
stage65_has_pattern "$KB" "cache_pools="
stage65_has_pattern "$KB" "placement_groups="
stage65_has_pattern "$KB" "lifetime="
stage65_has_pattern "$KB" "recompute_ok="
stage65_has_pattern "$DOC" "results/stage6"

# Stage 6: verify placement/lifetime symbols in broad patch 0007
required_stage6_symbols=(
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:enum kairo_lifetime_class"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:struct kairo_placement_hint"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:blk_mq_kairo_default_placement"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:kairo_has_model_id"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:kairo_has_session_id"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:kairo_is_short_lived"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:kairo_is_session_lived"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:kairo_is_model_lived"
  "$PATCH_DIR/0007-rfc-kairo-placement-lifetime-hints.patch:kairo_recompute_ok"
)

for entry in "${required_stage6_symbols[@]}"; do
  patch="${entry%%:*}"
  symbol="${entry#*:}"
  grep -q "$symbol" "$patch" || fail "missing Stage 6 symbol $symbol in $(basename "$patch")"
done

# Stage 6: verify placement/lifetime scaffold counters in broad patch 0009
required_stage6_sysfs_names=(
  "kairo_placement_hints"
  "kairo_lifetime_short_count"
  "kairo_lifetime_session_count"
  "kairo_lifetime_model_count"
  "kairo_lifetime_persistent_count"
  "kairo_recompute_ok_count"
  "kairo_has_model_id_count"
  "kairo_has_session_id_count"
  "kairo_has_cache_pool_count"
)

for name in "${required_stage6_sysfs_names[@]}"; do
  grep -q "$name" "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch" || \
    fail "missing Stage 6 sysfs counter $name in broad patch 0009"
done

# Stage 7: verify backend mapping symbols in broad patch 0008
required_stage7_symbols=(
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:enum kairo_backend_class"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:struct kairo_backend_hint"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:kairo_backend_class_from_request"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:kairo_backend_hint_from_request"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_prepare_backend_hint"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_apply_backend_hint"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_streams_supported"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_fdp_supported"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_zns_supported"
)

for entry in "${required_stage7_symbols[@]}"; do
  patch="${entry%%:*}"
  symbol="${entry#*:}"
  grep -q "$symbol" "$patch" || fail "missing Stage 7 symbol $symbol in $(basename "$patch")"
done

# Stage 7: verify backend mapping scaffold counters in broad patch 0009
required_stage7_sysfs_names=(
  "kairo_backend_mapping_attempts"
  "kairo_backend_noop_fallbacks"
  "kairo_backend_stream_hints"
  "kairo_backend_fdp_hints"
  "kairo_backend_zns_hints"
  "kairo_backend_short_lived"
  "kairo_backend_session_local"
  "kairo_backend_model_local"
  "kairo_backend_recomputable"
  "kairo_backend_persistent"
)

for name in "${required_stage7_sysfs_names[@]}"; do
  grep -q "$name" "$PATCH_DIR/0009-rfc-kairo-sysfs-debug-counters.patch" || \
    fail "missing Stage 7 sysfs counter $name in broad patch 0009"
done

# Stage 7.5: verify experiment harness
stage7_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 7: missing pattern '$pattern' in $(basename "$file")"
}

stage7_file_exists() {
  [[ -f "$1" ]] || fail "Stage 7: missing file: $1"
}

R7SE="$SCRIPT_DIR/run_stage7_backend_mapping_experiment.sh"
P7SP="$SCRIPT_DIR/parse_stage7_backend_summary.py"
DOC7="$REPO_ROOT/docs/stage7_generic_nvme_backend_mapping.md"

stage7_file_exists "$R7SE"
stage7_file_exists "$P7SP"
stage7_file_exists "$DOC7"
stage7_has_pattern "$R7SE" "results/stage7"
stage7_has_pattern "$R7SE" "block-device"
stage7_has_pattern "$P7SP" "--csv"
stage7_has_pattern "$P7SP" "--pretty"
stage7_has_pattern "$KB" "backend-mode"
stage7_has_pattern "$KB" "backend_mode="
stage7_has_pattern "$KB" "backend_class="
stage7_has_pattern "$DOC7" "backend class"
stage7_has_pattern "$DOC7" "KAIRO_BACKEND_NONE"

required_sysfs_names=(
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
)

for name in "${required_sysfs_names[@]}"; do
  grep -q "$name" "$FOUNDATION_DIR/0004-kairo-mq-deadline-sysfs-counters.patch" || \
    fail "missing sysfs name $name in foundation patch 0004"
done

if [[ -z "$LINUX_TREE" ]]; then
  echo "[kairo] patch metadata checks passed"
  echo "[kairo] tip: pass a Linux 6.8.x source tree to run foundation apply checks"
  exit 0
fi

[[ -d "$LINUX_TREE" ]] || fail "Linux source tree not found: $LINUX_TREE"

required_linux_files=(
  "$LINUX_TREE/block/mq-deadline.c"
  "$LINUX_TREE/block/blk-mq.c"
  "$LINUX_TREE/include/linux/blk-mq.h"
  "$LINUX_TREE/include/linux/blk_types.h"
)

for file in "${required_linux_files[@]}"; do
  [[ -f "$file" ]] || fail "expected Linux file missing: $file"
done

scratch_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$scratch_dir"
}
trap cleanup EXIT

mkdir -p "$scratch_dir/block" "$scratch_dir/include/linux"
cp "$LINUX_TREE/block/mq-deadline.c" "$scratch_dir/block/mq-deadline.c"
cp "$LINUX_TREE/block/blk-mq.c" "$scratch_dir/block/blk-mq.c"
cp "$LINUX_TREE/include/linux/blk-mq.h" "$scratch_dir/include/linux/blk-mq.h"
cp "$LINUX_TREE/include/linux/blk_types.h" "$scratch_dir/include/linux/blk_types.h"

for patch in "${required_foundation_patches[@]}"; do
  echo "[kairo] checking patch applicability: $(basename "$patch")"
  git -C "$scratch_dir" apply --check --recount "$patch"
  git -C "$scratch_dir" apply --recount "$patch"
done

echo "[kairo] foundation patch applicability checks passed"
