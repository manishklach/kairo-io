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
  "0010-rfc-kairo-request-classification-real.patch"
  "0011-rfc-kairo-write-antistarvation-deadline.patch"
  "0012-rfc-kairo-nvme-tag-reservation.patch"
  "0013-rfc-kairo-mq-deadline-dispatch-O1.patch"
  "0014-rfc-kairo-io-uring-sqe-hint-flag.patch"
  "0015-rfc-kairo-merge-bias-real.patch"
  "0016-rfc-kairo-bpf-dispatch-hook.patch"
  "0017-rfc-kairo-tracepoints-observability.patch"
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
  "$REPO_ROOT/docs/validation_snapshot.md"
  "$REPO_ROOT/kernel/integration/linux-6.8/apply_foundation_stack.sh"
  "$REPO_ROOT/kernel/integration/linux-6.8/validate_foundation_stack.sh"
  "$REPO_ROOT/kernel/integration/linux-6.8/build_foundation_objects.sh"
  "$REPO_ROOT/kernel/integration/linux-6.8/smoke_foundation_stack.sh"
  "$REPO_ROOT/scripts/check_wsl_environment.sh"
  "$REPO_ROOT/scripts/run_wsl_validation_snapshot.sh"
  "$REPO_ROOT/scripts/parse_validation_snapshot.py"
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
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:struct kairo_backend_caps"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:kairo_backend_class_from_request"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:kairo_backend_hint_from_request"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:kairo_backend_hint_apply_caps"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_prepare_backend_hint"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_apply_backend_hint"
  "$PATCH_DIR/0008-rfc-kairo-nvme-zns-fdp-mapping.patch:nvme_kairo_get_backend_caps"
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

# Stage 7.5: verify NVMe hook audit, caps abstraction, and validator
stage75_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 7.5: missing pattern '$pattern' in $(basename "$file")"
}

stage75_file_exists() {
  [[ -f "$1" ]] || fail "Stage 7.5: missing file: $1"
}

AUDIT_DOC="$REPO_ROOT/docs/stage7_5_nvme_hook_audit.md"
AUDIT_SH="$REPO_ROOT/kernel/integration/linux-6.8/audit_nvme_hooks.sh"
VALIDATOR_PY="$REPO_ROOT/scripts/validate_stage7_backend_mapping.py"

stage75_file_exists "$AUDIT_DOC"
stage75_file_exists "$AUDIT_SH"
stage75_file_exists "$VALIDATOR_PY"
stage75_has_pattern "$AUDIT_DOC" "kairo_backend_caps"
stage75_has_pattern "$AUDIT_DOC" "COMPILE-TARGET CANDIDATE"
stage75_has_pattern "$AUDIT_DOC" "CONCEPTUAL HOOK"
stage75_has_pattern "$AUDIT_SH" "check_symbol_present"
stage75_has_pattern "$AUDIT_SH" "check_symbol_absent"

# Run Python validator
if command -v python3 &>/dev/null; then
  echo "[kairo] running Stage 7.5 Python validator..."
  python3 "$VALIDATOR_PY" || fail "Stage 7.5 Python validator failed"
else
  echo "[kairo] python3 not found; skipping Stage 7.5 Python validator"
fi

# Stage 7 harness checks
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

# Stage 8: verify tracepoint patch and scripts (renumbered to 0017)
stage8_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 8: missing pattern '$pattern' in $(basename "$file")"
}

stage8_file_exists() {
  [[ -f "$1" ]] || fail "Stage 8: missing file: $1"
}

P10="$PATCH_DIR/0017-rfc-kairo-tracepoints-observability.patch"
DOC8="$REPO_ROOT/docs/stage8_kernel_observability.md"
R8SE="$REPO_ROOT/scripts/run_stage8_trace_experiment.sh"
P8SP="$REPO_ROOT/scripts/parse_stage8_trace_log.py"
AUDIT_TP="$REPO_ROOT/kernel/integration/linux-6.8/audit_tracepoints.sh"
BT_LATENCY="$REPO_ROOT/scripts/bpftrace/kairo_latency.bt"
BT_DISPATCH="$REPO_ROOT/scripts/bpftrace/kairo_dispatch.bt"
BT_BACKEND="$REPO_ROOT/scripts/bpftrace/kairo_backend.bt"

stage8_file_exists "$P10"
stage8_file_exists "$DOC8"
stage8_file_exists "$R8SE"
stage8_file_exists "$P8SP"
stage8_file_exists "$AUDIT_TP"
stage8_file_exists "$BT_LATENCY"
stage8_file_exists "$BT_DISPATCH"
stage8_file_exists "$BT_BACKEND"
stage8_has_pattern "$P10" "TRACE_SYSTEM kairo"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_request_classified"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_scheduler_decision"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_decode_dispatch"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_prefetch_dispatch"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_write_demoted"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_merge_decision"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_semantic_classified"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_placement_classified"
stage8_has_pattern "$P10" "TRACE_EVENT(kairo_backend_mapped"
stage8_has_pattern "$DOC8" "tracepoints"
stage8_has_pattern "$R8SE" "results/stage8"
stage8_has_pattern "$R8SE" "trace-mode"
stage8_has_pattern "$R8SE" "bpftrace"
stage8_has_pattern "$P8SP" "--csv"
stage8_has_pattern "$P8SP" "--pretty"
stage8_has_pattern "$AUDIT_TP" "kairo_request_classified"
stage8_has_pattern "$BT_LATENCY" "kairo_decode_dispatch"
stage8_has_pattern "$BT_DISPATCH" "kairo_scheduler_decision"
stage8_has_pattern "$BT_BACKEND" "kairo_backend_mapped"

# Stage 10: verify adaptive latency controller
stage10_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 10: missing pattern '$pattern' in $(basename "$file")"
}

stage10_file_exists() {
  [[ -f "$1" ]] || fail "Stage 10: missing file: $1"
}

P18="$PATCH_DIR/0018-rfc-kairo-adaptive-latency-controller.patch"
DOC10="$REPO_ROOT/docs/stage10_adaptive_latency_controller.md"
R10SE="$REPO_ROOT/scripts/run_stage10_latency_controller_experiment.sh"
P10SP="$REPO_ROOT/scripts/parse_stage10_latency_controller_summary.py"

stage10_file_exists "$P18"
stage10_file_exists "$DOC10"
stage10_file_exists "$R10SE"
stage10_file_exists "$P10SP"
stage10_has_pattern "$P18" "enum kairo_controller_mode"
stage10_has_pattern "$P18" "struct kairo_latency_controller"
stage10_has_pattern "$P18" "kairo_target_decode_p99_us"
stage10_has_pattern "$P18" "adaptive_decode_budget"
stage10_has_pattern "$P18" "adaptive_prefetch_budget"
stage10_has_pattern "$P18" "controller_updates"
stage10_has_pattern "$P18" "controller_boost_events"
stage10_has_pattern "$P18" "controller_relax_events"
stage10_has_pattern "$P18" "controller_throttle_prefetch_events"
stage10_has_pattern "$P18" "controller_release_write_events"
stage10_has_pattern "$P18" "controller_insufficient_samples"
stage10_has_pattern "$DOC10" "adaptive scheduling controller"
stage10_has_pattern "$R10SE" "results/stage10"
stage10_has_pattern "$R10SE" "block-device"
stage10_has_pattern "$R10SE" "controller-adaptive"
stage10_has_pattern "$P10SP" "--csv"
stage10_has_pattern "$P10SP" "--pretty"
stage10_has_pattern "$P10SP" "kairo_controller_updates_delta"

# Verify collect_kairo_counters.sh includes controller counters
grep -qF "kairo_controller_updates" "$REPO_ROOT/scripts/collect_kairo_counters.sh" || \
  fail "Stage 10: collect_kairo_counters.sh missing kairo_controller_updates"
grep -qF "kairo_controller_boost_events" "$REPO_ROOT/scripts/collect_kairo_counters.sh" || \
  fail "Stage 10: collect_kairo_counters.sh missing kairo_controller_boost_events"

# Verify docs reference Stage 10
grep -qF "Stage 10" "$DOC10" || fail "Stage 10: doc missing 'Stage 10' reference"

# Stage 11: verify foundation tracepoints
stage11_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 11: missing pattern '$pattern' in $(basename "$file")"
}

stage11_file_exists() {
  [[ -f "$1" ]] || fail "Stage 11: missing file: $1"
}

FP5="$FOUNDATION_DIR/0005-kairo-foundation-tracepoints.patch"
P22="$PATCH_DIR/0022-rfc-kairo-foundation-tracepoints-linux-6.8.patch"
DOC11="$REPO_ROOT/docs/stage11_foundation_tracepoints.md"
V11TP="$REPO_ROOT/kernel/integration/linux-6.8/validate_foundation_tracepoints.sh"
R11SE="$REPO_ROOT/scripts/run_stage11_foundation_trace_experiment.sh"
P11SP="$REPO_ROOT/scripts/parse_stage11_foundation_trace_summary.py"

stage11_file_exists "$FP5"
stage11_file_exists "$P22"
stage11_file_exists "$DOC11"
stage11_file_exists "$V11TP"
stage11_file_exists "$R11SE"
stage11_file_exists "$P11SP"
stage11_has_pattern "$FP5" "TRACE_EVENT(kairo_request_classified"
stage11_has_pattern "$FP5" "TRACE_EVENT(kairo_decode_dispatch"
stage11_has_pattern "$FP5" "TRACE_EVENT(kairo_prefetch_dispatch"
stage11_has_pattern "$FP5" "TRACE_EVENT(kairo_write_demoted"
stage11_has_pattern "$P22" "TRACE_EVENT(kairo_request_classified"
stage11_has_pattern "$P22" "TRACE_EVENT(kairo_decode_dispatch"
stage11_has_pattern "$P22" "TRACE_EVENT(kairo_prefetch_dispatch"
stage11_has_pattern "$P22" "TRACE_EVENT(kairo_write_demoted"
stage11_has_pattern "$DOC11" "compile-targeted"
stage11_has_pattern "$V11TP" "TRACE_EVENT("
stage11_has_pattern "$R11SE" "tracepoints_available"
stage11_has_pattern "$R11SE" "results/stage11"
stage11_has_pattern "$P11SP" "--csv"

# Verify apply_foundation_stack.sh handles --with-tracepoints
grep -qF -- "--with-tracepoints" "$REPO_ROOT/kernel/integration/linux-6.8/apply_foundation_stack.sh" || \
  fail "Stage 11: apply_foundation_stack.sh missing --with-tracepoints"

# Verify foundation README mentions tracepoints
grep -qF "0005-kairo-foundation-tracepoints" "$FOUNDATION_DIR/README.md" || \
  fail "Stage 11: foundation README missing tracepoint patch reference"

# Stage 12: verify model/session fairness
stage12_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 12: missing pattern '$pattern' in $(basename "$file")"
}

stage12_file_exists() {
  [[ -f "$1" ]] || fail "Stage 12: missing file: $1"
}

P20="$PATCH_DIR/0020-rfc-kairo-model-session-fairness.patch"
DOC12="$REPO_ROOT/docs/stage12_model_session_fairness.md"
R12SE="$REPO_ROOT/scripts/run_stage12_fairness_experiment.sh"
P12SP="$REPO_ROOT/scripts/parse_stage12_fairness_summary.py"

stage12_file_exists "$P20"
stage12_file_exists "$DOC12"
stage12_file_exists "$R12SE"
stage12_file_exists "$P12SP"
stage12_has_pattern "$P20" "struct kairo_fair_entity"
stage12_has_pattern "$P20" "struct kairo_fairness_state"
stage12_has_pattern "$P20" "kairo_fairness_allow_decode"
stage12_has_pattern "$P20" "kairo_fairness_throttle_prefetch"
stage12_has_pattern "$P20" "kairo_fairness_demote_write"
stage12_has_pattern "$P20" "kairo_fairness_account_dispatch"
stage12_has_pattern "$P20" "kairo_fairness_refill_if_needed"
stage12_has_pattern "$P20" "kairo_fairness_refills"
stage12_has_pattern "$P20" "kairo_fairness_model_throttles"
stage12_has_pattern "$P20" "kairo_fairness_session_throttles"
stage12_has_pattern "$P20" "kairo_noisy_session_events"
stage12_has_pattern "$P20" "kairo_protected_decode_dispatches"
stage12_has_pattern "$P20" "kairo_prefetch_fairness_throttles"
stage12_has_pattern "$P20" "kairo_write_fairness_demotions"
stage12_has_pattern "$DOC12" "per-model"
stage12_has_pattern "$R12SE" "results/stage12"
stage12_has_pattern "$R12SE" "block-device"
stage12_has_pattern "$R12SE" "--noisy-multiplier"
stage12_has_pattern "$P12SP" "--csv"
stage12_has_pattern "$P12SP" "--pretty"
stage12_has_pattern "$P12SP" "kairo_fairness_refills_delta"

# Verify collect_kairo_counters.sh includes fairness counters
grep -qF "kairo_fairness_refills" "$REPO_ROOT/scripts/collect_kairo_counters.sh" || \
  fail "Stage 12: collect_kairo_counters.sh missing kairo_fairness_refills"

# Stage 13: verify decode latency histogram
stage13_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 13: missing pattern '$pattern' in $(basename "$file")"
}

stage13_file_exists() {
  [[ -f "$1" ]] || fail "Stage 13: missing file: $1"
}

P23="$PATCH_DIR/0023-rfc-kairo-decode-latency-histogram.patch"
DOC13="$REPO_ROOT/docs/stage13_decode_latency_histogram.md"
R13SE="$REPO_ROOT/scripts/run_stage13_latency_histogram_experiment.sh"
P13SP="$REPO_ROOT/scripts/parse_stage13_latency_histogram_summary.py"

stage13_file_exists "$P23"
stage13_file_exists "$DOC13"
stage13_file_exists "$R13SE"
stage13_file_exists "$P13SP"
stage13_has_pattern "$P23" "enum kairo_decode_latency_bucket"
stage13_has_pattern "$P23" "struct kairo_latency_histogram"
stage13_has_pattern "$P23" "kairo_latency_histogram_add"
stage13_has_pattern "$P23" "kairo_latency_histogram_estimate_percentile"
stage13_has_pattern "$P23" "kairo_latency_histogram_reset"
stage13_has_pattern "$DOC13" "bucketed histogram"
stage13_has_pattern "$R13SE" "results/stage13"
stage13_has_pattern "$R13SE" "block-device"
stage13_has_pattern "$P13SP" "--csv"
stage13_has_pattern "$P13SP" "--pretty"
stage13_has_pattern "$P13SP" "decode_lat_0_10us"

# Verify bench prints histogram buckets
grep -qF "decode_lat_0_10us=" "$REPO_ROOT/bench/kairo_bench.c" || \
  fail "Stage 13: bench missing decode_lat_0_10us="

# Verify collect_kairo_counters.sh includes histogram bucket counters
grep -qF "kairo_decode_lat_0_10us" "$REPO_ROOT/scripts/collect_kairo_counters.sh" || \
  fail "Stage 13: collect_kairo_counters.sh missing kairo_decode_lat_0_10us"

# Verify WSL validation includes stage13_dryrun
grep -qF "stage13_dryrun" "$REPO_ROOT/scripts/run_wsl_validation_snapshot.sh" || \
  fail "Stage 13: run_wsl_validation_snapshot.sh missing stage13_dryrun"

# Stage 14: verify controller feedback wiring
stage14_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 14: missing pattern '$pattern' in $(basename "$file")"
}

stage14_file_exists() {
  [[ -f "$1" ]] || fail "Stage 14: missing file: $1"
}

P24="$PATCH_DIR/0024-rfc-kairo-controller-feedback-wiring.patch"
DOC14="$REPO_ROOT/docs/stage14_controller_feedback_wiring.md"
R14SE="$REPO_ROOT/scripts/run_stage14_controller_feedback_experiment.sh"
P14SP="$REPO_ROOT/scripts/parse_stage14_controller_feedback_summary.py"

stage14_file_exists "$P24"
stage14_file_exists "$DOC14"
stage14_file_exists "$R14SE"
stage14_file_exists "$P14SP"
stage14_has_pattern "$P24" "kairo_mark_classify_time"
stage14_has_pattern "$P24" "kairo_mark_dispatch_time"
stage14_has_pattern "$P24" "kairo_decode_queue_latency_us"
stage14_has_pattern "$P24" "dd_kairo_controller_note_decode_latency"
stage14_has_pattern "$P24" "controller_latency_samples"
stage14_has_pattern "$P24" "controller_missing_timestamp"
stage14_has_pattern "$P24" "kairo_controller_sample"
stage14_has_pattern "$DOC14" "classify_time_ns"
stage14_has_pattern "$R14SE" "results/stage14"
stage14_has_pattern "$R14SE" "block-device"
stage14_has_pattern "$P14SP" "--csv"
stage14_has_pattern "$P14SP" "--pretty"
stage14_has_pattern "$P14SP" "controller_latency_samples_delta"

# Verify collect_kairo_counters.sh includes feedback counters
grep -qF "kairo_controller_latency_samples" "$REPO_ROOT/scripts/collect_kairo_counters.sh" || \
  fail "Stage 14: collect_kairo_counters.sh missing kairo_controller_latency_samples"

# Verify WSL validation includes stage14_dryrun
grep -qF "stage14_dryrun" "$REPO_ROOT/scripts/run_wsl_validation_snapshot.sh" || \
  fail "Stage 14: run_wsl_validation_snapshot.sh missing stage14_dryrun"

# Stage 15: verify fairness accounting and sysfs wiring
stage15_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Stage 15: missing pattern '$pattern' in $(basename "$file")"
}

stage15_file_exists() {
  [[ -f "$1" ]] || fail "Stage 15: missing file: $1"
}

P25="$PATCH_DIR/0025-rfc-kairo-fairness-accounting-sysfs.patch"
DOC15="$REPO_ROOT/docs/stage15_fairness_accounting_sysfs.md"
R15SE="$REPO_ROOT/scripts/run_stage15_fairness_accounting_experiment.sh"
P15SP="$REPO_ROOT/scripts/parse_stage15_fairness_accounting_summary.py"

stage15_file_exists "$P25"
stage15_file_exists "$DOC15"
stage15_file_exists "$R15SE"
stage15_file_exists "$P15SP"
stage15_has_pattern "$P25" "kairo_fairness_enable"
stage15_has_pattern "$P25" "kairo_model_decode_credit"
stage15_has_pattern "$P25" "kairo_session_decode_credit"
stage15_has_pattern "$P25" "kairo_fairness_refill_ms"
stage15_has_pattern "$P25" "kairo_noisy_session_threshold"
stage15_has_pattern "$P25" "kairo_fairness_refills"
stage15_has_pattern "$P25" "kairo_fairness_model_throttles"
stage15_has_pattern "$P25" "kairo_fairness_session_throttles"
stage15_has_pattern "$P25" "kairo_noisy_session_events"
stage15_has_pattern "$P25" "kairo_protected_decode_dispatches"
stage15_has_pattern "$P25" "kairo_prefetch_fairness_throttles"
stage15_has_pattern "$P25" "kairo_write_fairness_demotions"
stage15_has_pattern "$DOC15" "Why Fairness Needs Sysfs Visibility"
stage15_has_pattern "$R15SE" "results/stage15"
stage15_has_pattern "$R15SE" "block-device"
stage15_has_pattern "$R15SE" "--noisy-multiplier"
stage15_has_pattern "$P15SP" "--csv"
stage15_has_pattern "$P15SP" "--pretty"
stage15_has_pattern "$P15SP" "DELTA_FIELDS"

# Verify collect_kairo_counters.sh includes fairness counters
grep -qF "kairo_fairness_refills" "$REPO_ROOT/scripts/collect_kairo_counters.sh" || \
  fail "Stage 15: collect_kairo_counters.sh missing kairo_fairness_refills"

# Verify WSL validation includes stage15_dryrun
grep -qF "stage15_dryrun" "$REPO_ROOT/scripts/run_wsl_validation_snapshot.sh" || \
  fail "Stage 15: run_wsl_validation_snapshot.sh missing stage15_dryrun"

# Stage 9: verify WSL validation files
[[ -f "$REPO_ROOT/scripts/check_wsl_environment.sh" ]] || fail "Stage 9: missing scripts/check_wsl_environment.sh"
[[ -f "$REPO_ROOT/scripts/run_wsl_validation_snapshot.sh" ]] || fail "Stage 9: missing scripts/run_wsl_validation_snapshot.sh"
[[ -f "$REPO_ROOT/scripts/parse_validation_snapshot.py" ]] || fail "Stage 9: missing scripts/parse_validation_snapshot.py"
[[ -f "$REPO_ROOT/docs/validation_snapshot.md" ]] || fail "Stage 9: missing docs/validation_snapshot.md"
grep -qF -- "run_wsl_validation_snapshot.sh" "$REPO_ROOT/README.md" || \
  fail "Stage 9: README missing run_wsl_validation_snapshot.sh reference"

# Stage 9+: verify new supernova patches 0010-0016
stage9_has_pattern() {
  local file="$1" pattern="$2"
  grep -qF -- "$pattern" "$file" || fail "Supernova: missing pattern '$pattern' in $(basename "$file")"
}

stage9_file_exists() {
  [[ -f "$1" ]] || fail "Supernova: missing file: $1"
}

# Patch 0010: real classification
stage9_has_pattern "$PATCH_DIR/0010-rfc-kairo-request-classification-real.patch" \
  "kairo_classify_request" "0010: real classification helper"

# Patch 0011: write anti-starvation
stage9_has_pattern "$PATCH_DIR/0011-rfc-kairo-write-antistarvation-deadline.patch" \
  "kairo_write_force_deadline_ns" "0011: write anti-starvation deadline"

# Patch 0012: tag reservation
stage9_has_pattern "$PATCH_DIR/0012-rfc-kairo-nvme-tag-reservation.patch" \
  "kairo_tag_reserve_allowed" "0012: tag reservation"

# Patch 0013: O(1) decode dispatch
stage9_has_pattern "$PATCH_DIR/0013-rfc-kairo-mq-deadline-dispatch-O1.patch" \
  "kairo_decode_head" "0013: O(1) decode FIFO"

# Patch 0014: io_uring SQE hint
stage9_has_pattern "$PATCH_DIR/0014-rfc-kairo-io-uring-sqe-hint-flag.patch" \
  "IORING_SQE_KAIRO_CLASS" "0014: SQE hint flag"

# Patch 0015: real merge bias
stage9_has_pattern "$PATCH_DIR/0015-rfc-kairo-merge-bias-real.patch" \
  "kairo_attempt_forced_merge" "0015: real merge bias"

# Patch 0016: BPF dispatch hook
stage9_has_pattern "$PATCH_DIR/0016-rfc-kairo-bpf-dispatch-hook.patch" \
  "BPF_PROG_TYPE_KAIRO_SCHED" "0016: BPF dispatch hook"

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
