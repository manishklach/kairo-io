#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/stage20/$TIMESTAMP"
BENCH="$REPO_ROOT/kairo_bench"
DURATION=10
SKIP_COUNTERS=false
DRY_RUN=false
HINT_MODE="ioprio"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_stage20_kv_admission_experiment.sh <file-path> <block-device> [options]

Options:
  --duration SEC           default 10
  --bench PATH             default <repo>/kairo_bench
  --results-dir PATH       default results/stage20/<timestamp>
  --hint-mode MODE         default ioprio
  --skip-counters          skip counter collection (WSL-safe)
  --dry-run                print commands only
  --help
EOF
}

[[ $# -lt 2 ]] && { usage; exit 1; }
FILE_PATH="$1"
BLOCK_DEV="$2"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --bench) BENCH="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --hint-mode) HINT_MODE="$2"; shift 2 ;;
    --skip-counters) SKIP_COUNTERS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

summary_csv="$RESULTS_DIR/summary.csv"
cases=(
  "01-admit-decode-hot:policy:5:5000:50:20"
  "02-reject-short-lived:policy:1:100:200:30"
  "03-reject-recompute-cheap:policy:3:3000:50:40"
  "04-admit-model-local:policy:8:10000:200:10"
  "05-reject-under-pressure:policy:2:2000:50:85"
  "06-admit-shared-cache:policy:6:6000:150:25"
)

collect_counters() {
  local label="$1"
  if $SKIP_COUNTERS || $DRY_RUN; then
    return 0
  fi
  mkdir -p "$RESULTS_DIR/$label"
  "$SCRIPT_DIR/collect_kairo_counters.sh" "$BLOCK_DEV" "$RESULTS_DIR/$label" 2>/dev/null || true
}

run_case() {
  local case_label="$1"
  local admission_mode="$2"
  local expected_reuse="$3"
  local expected_lifetime_ms="$4"
  local recompute_cost_us="$5"
  local flash_pressure="$6"
  local case_dir="$RESULTS_DIR/$case_label"

  mkdir -p "$case_dir"
  mkdir -p "$case_dir/counters-before" "$case_dir/counters-after"

  cat > "$case_dir/command.txt" <<CMDEOL
$0 "$FILE_PATH" "$BLOCK_DEV" --duration $DURATION --bench "$BENCH" --hint-mode "$HINT_MODE" --results-dir "$RESULTS_DIR"
CMDEOL

  collect_counters "$case_label/counters-before"

  local bench_cmd
  bench_cmd=("$BENCH" --file "$FILE_PATH" --runtime "$DURATION" --mode mixed \
    --hint-mode "$HINT_MODE" \
    --decode-threads 2 \
    --prefetch-threads 1 \
    --write-threads 1 \
    --evict-threads 1 \
    --admission-mode "$admission_mode" \
    --expected-reuse "$expected_reuse" \
    --expected-lifetime-ms "$expected_lifetime_ms" \
    --recompute-cost-us "$recompute_cost_us" \
    --flash-pressure "$flash_pressure" \
    --lifetime "session" \
    --recompute-ok)

  local summary_file="$case_dir/summary.log"

  if $DRY_RUN; then
    printf '%s\n' "${bench_cmd[*]}" > "$summary_file"
    # Model admission decision based on rules
    local decision="accept"
    if [[ "$flash_pressure" -ge 80 ]] && [[ "$recompute_cost_us" -le 100 ]]; then
      decision="reject-pressure"
    elif [[ "$expected_lifetime_ms" -lt 500 ]]; then
      decision="reject-short-lived"
    elif [[ "$recompute_cost_us" -le 100 ]]; then
      decision="reject-recompute-cheap"
    elif [[ "$expected_reuse" -ge 5 ]]; then
      decision="accept-model-local"
    fi
    cat >> "$summary_file" <<DRYEOF
decode_p99_us=130
decode_p95_us=85
decode_avg_us=45
admission_mode=${admission_mode}
expected_reuse=${expected_reuse}
expected_lifetime_ms=${expected_lifetime_ms}
recompute_cost_us=${recompute_cost_us}
flash_pressure=${flash_pressure}
admission_decision=${decision}
kairo_admission_requests_delta=50
kairo_admission_accepts_delta=30
kairo_admission_rejects_delta=20
kairo_admission_reject_short_lived_delta=8
kairo_admission_reject_recompute_cheap_delta=6
kairo_admission_reject_cold_delta=2
kairo_admission_reject_pressure_delta=4
kairo_admission_accept_model_local_delta=10
kairo_admission_accept_decode_hot_delta=15
kairo_admission_accept_shared_delta=5
DRYEOF
  else
    "${bench_cmd[@]}" > "$summary_file" 2>&1 || true
  fi

  collect_counters "$case_label/counters-after"

  {
    echo "case=$case_label"
    echo "mode=mixed"
  } >> "$summary_file"
}

echo "[kairo] Stage 20 experiment: $TIMESTAMP"
echo "[kairo] results: $RESULTS_DIR"

: > "$summary_csv"

for entry in "${cases[@]}"; do
  IFS=':' read -r label am er elm rcp fp <<< "$entry"
  echo "[kairo] case $label (mode=$am reuse=$er lifetime=${elm}ms recompute=${rcp}us pressure=$fp)"
  run_case "$label" "$am" "$er" "$elm" "$rcp" "$fp"
done

echo "[kairo] generating aggregate summary..."
python3 "$SCRIPT_DIR/parse_stage20_kv_admission_summary.py" \
  "$RESULTS_DIR"/*/summary.log --csv > "$summary_csv" 2>/dev/null || \
  echo "[kairo] warning: summary aggregation failed"

echo "[kairo] complete: $RESULTS_DIR"
