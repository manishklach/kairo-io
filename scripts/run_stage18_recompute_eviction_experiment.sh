#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/stage18/$TIMESTAMP"
BENCH="$REPO_ROOT/kairo_bench"
DURATION=10
SKIP_COUNTERS=false
DRY_RUN=false
HINT_MODE="ioprio"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_stage18_recompute_eviction_experiment.sh <file-path> <block-device> [options]

Options:
  --duration SEC           default 10
  --bench PATH             default <repo>/kairo_bench
  --results-dir PATH       default results/stage18/<timestamp>
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
  "01-ordinary-eviction:mixed:2:1:1:1:none:0"
  "02-recomputable-short-lived:mixed:2:1:1:1:recompute-aware:30"
  "03-recomputable-session-cache:mixed:2:1:1:1:recompute-aware:50"
  "04-model-cache-avoid:mixed:2:1:1:1:lifetime:70"
  "05-decode-pressure-eviction-defer:mixed:3:2:1:1:mixed:80"
  "06-mixed-eviction-pressure:mixed:2:2:2:2:mixed:50"
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
  local mode="$2"
  local decode_threads="$3"
  local prefetch_threads="$4"
  local write_threads="$5"
  local evict_threads="$6"
  local eviction_policy="$7"
  local eviction_pressure="$8"
  local case_dir="$RESULTS_DIR/$case_label"

  mkdir -p "$case_dir"
  mkdir -p "$case_dir/counters-before" "$case_dir/counters-after"

  cat > "$case_dir/command.txt" <<CMDEOL
$0 "$FILE_PATH" "$BLOCK_DEV" --duration $DURATION --bench "$BENCH" --hint-mode "$HINT_MODE" --results-dir "$RESULTS_DIR"
CMDEOL

  collect_counters "$case_label/counters-before"

  local bench_cmd
  bench_cmd=("$BENCH" --file "$FILE_PATH" --runtime "$DURATION" --mode "$mode" \
    --hint-mode "$HINT_MODE" \
    --decode-threads "$decode_threads" \
    --prefetch-threads "$prefetch_threads" \
    --write-threads "$write_threads" \
    --evict-threads "$evict_threads" \
    --eviction-policy "$eviction_policy" \
    --eviction-pressure "$eviction_pressure" \
    --lifetime "session" \
    --recompute-ok)

  local summary_file="$case_dir/summary.log"

  if $DRY_RUN; then
    printf '%s\n' "${bench_cmd[*]}" > "$summary_file"
    cat >> "$summary_file" <<DRYEOF
decode_p99_us=125
decode_p95_us=80
decode_avg_us=45
write_MBps=120
evict_MBps=45
eviction_policy=${eviction_policy}
eviction_recompute_ok=1
eviction_lifetime=session
eviction_score_model=medium
eviction_pressure=${eviction_pressure}
kairo_eviction_decisions_delta=100
kairo_eviction_recomputable_short_delta=60
kairo_eviction_recomputable_session_delta=20
kairo_eviction_ephemeral_prefetch_delta=10
kairo_eviction_session_cache_delta=5
kairo_eviction_model_cache_delta=3
kairo_eviction_persistent_avoided_delta=2
kairo_eviction_decode_hot_deferred_delta=15
kairo_eviction_discard_preferred_delta=8
kairo_eviction_writeback_required_delta=0
DRYEOF
  else
    "${bench_cmd[@]}" > "$summary_file" 2>&1 || true
  fi

  collect_counters "$case_label/counters-after"

  {
    echo "case=$case_label"
    echo "mode=$mode"
  } >> "$summary_file"
}

echo "[kairo] Stage 18 experiment: $TIMESTAMP"
echo "[kairo] results: $RESULTS_DIR"

: > "$summary_csv"

for entry in "${cases[@]}"; do
  IFS=':' read -r label mode dt pt wt et ep epr <<< "$entry"
  echo "[kairo] case $label ($mode, decode=$dt prefetch=$pt write=$wt evict=$et policy=$ep pressure=$epr)"
  run_case "$label" "$mode" "$dt" "$pt" "$wt" "$et" "$ep" "$epr"
done

echo "[kairo] generating aggregate summary..."
python3 "$SCRIPT_DIR/parse_stage18_recompute_eviction_summary.py" \
  "$RESULTS_DIR"/*/summary.log --csv > "$summary_csv" 2>/dev/null || \
  echo "[kairo] warning: summary aggregation failed"

echo "[kairo] complete: $RESULTS_DIR"
