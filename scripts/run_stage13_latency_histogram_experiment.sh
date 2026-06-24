#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/stage13/$TIMESTAMP"
BENCH="$REPO_ROOT/kairo_bench"
DURATION=10
SKIP_COUNTERS=false
DRY_RUN=false
HINT_MODE="ioprio"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_stage13_latency_histogram_experiment.sh <file-path> <block-device> [options]

Options:
  --duration SEC           default 10
  --bench PATH             default <repo>/kairo_bench
  --results-dir PATH       default results/stage13/<timestamp>
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
  "01-decode-only:decode-only:4:0:0:0"
  "02-mixed-pressure:mixed:2:1:1:0"
  "03-prefetch-pressure:prefetch-pressure:2:4:1:0"
  "04-write-heavy:mixed:1:0:4:0"
  "05-multisession:multisession:2:2:1:1"
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
    --evict-threads "$evict_threads")

  local summary_file="$case_dir/summary.log"

  if $DRY_RUN; then
    printf '%s\n' "${bench_cmd[*]}" > "$summary_file"
    cat >> "$summary_file" <<DRYEOF
decode_lat_0_10us=0
decode_lat_10_25us=0
decode_lat_25_50us=0
decode_lat_50_100us=0
decode_lat_100_250us=0
decode_lat_250_500us=0
decode_lat_500_1000us=0
decode_lat_1ms_2ms=0
decode_lat_2ms_5ms=0
decode_lat_gt_5ms=0
decode_avg_us=0
decode_p95_us=0
decode_p99_us=0
decode_latency_samples=0
decode_latency_max_us=0
write_MBps=0
prefetch_read_MBps=0
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

echo "[kairo] Stage 13 experiment: $TIMESTAMP"
echo "[kairo] results: $RESULTS_DIR"

: > "$summary_csv"

for entry in "${cases[@]}"; do
  IFS=':' read -r label mode dt pt wt et <<< "$entry"
  echo "[kairo] case $label ($mode, decode=$dt prefetch=$pt write=$wt evict=$et)"
  run_case "$label" "$mode" "$dt" "$pt" "$wt" "$et"
done

# Aggregate summary
echo "[kairo] generating aggregate summary..."
python3 "$SCRIPT_DIR/parse_stage13_latency_histogram_summary.py" \
  "$RESULTS_DIR"/*/summary.log --csv > "$summary_csv" 2>/dev/null || \
  echo "[kairo] warning: summary aggregation failed"

echo "[kairo] complete: $RESULTS_DIR"
