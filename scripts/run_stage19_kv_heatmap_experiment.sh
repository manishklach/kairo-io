#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/stage19/$TIMESTAMP"
BENCH="$REPO_ROOT/kairo_bench"
DURATION=10
SKIP_COUNTERS=false
DRY_RUN=false
HINT_MODE="ioprio"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_stage19_kv_heatmap_experiment.sh <file-path> <block-device> [options]

Options:
  --duration SEC           default 10
  --bench PATH             default <repo>/kairo_bench
  --results-dir PATH       default results/stage19/<timestamp>
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
  "01-no-heatmap:mixed:2:1:1:0:none:50:50:10"
  "02-hot-decode-regions:mixed:4:1:1:0:region:80:60:5"
  "03-cold-recomputable-regions:mixed:1:2:2:1:region:20:30:60"
  "04-mixed-hot-cold-regions:mixed:3:2:1:1:region:50:50:30"
  "05-multisession-heatmap:multisession:2:2:1:1:region:50:50:30"
  "06-eviction-pressure-with-heatmap:mixed:2:2:2:2:region:40:40:40"
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
  local heatmap_mode="$7"
  local hot_ratio="$8"
  local region_reuse="$9"
  local cold_ratio="${10}"
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
    --heatmap-mode "$heatmap_mode" \
    --hot-region-ratio "$hot_ratio" \
    --region-reuse-ratio "$region_reuse" \
    --cold-region-ratio "$cold_ratio" \
    --lifetime "session" \
    --recompute-ok)

  local summary_file="$case_dir/summary.log"

  if $DRY_RUN; then
    printf '%s\n' "${bench_cmd[*]}" > "$summary_file"
    cat >> "$summary_file" <<DRYEOF
decode_p99_us=120
decode_p95_us=75
decode_avg_us=40
evict_MBps=35
heatmap_mode=${heatmap_mode}
hot_region_ratio=${hot_ratio}
region_reuse_ratio=${region_reuse}
cold_region_ratio=${cold_ratio}
kv_heat_hot=8
kv_heat_warm=12
kv_heat_cold=6
kv_heat_evictable=4
kv_heat_protected=2
kairo_kv_heatmap_hits_delta=250
kairo_kv_heatmap_misses_delta=10
kairo_kv_heatmap_updates_delta=260
kairo_kv_heatmap_decays_delta=5
kairo_kv_heatmap_evictable_regions_delta=4
kairo_kv_heatmap_protected_regions_delta=2
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

echo "[kairo] Stage 19 experiment: $TIMESTAMP"
echo "[kairo] results: $RESULTS_DIR"

: > "$summary_csv"

for entry in "${cases[@]}"; do
  IFS=':' read -r label mode dt pt wt et hm hr rr cr <<< "$entry"
  echo "[kairo] case $label ($mode, decode=$dt prefetch=$pt write=$wt evict=$et heat=$hm hot=$hr reuse=$rr cold=$cr)"
  run_case "$label" "$mode" "$dt" "$pt" "$wt" "$et" "$hm" "$hr" "$rr" "$cr"
done

echo "[kairo] generating aggregate summary..."
python3 "$SCRIPT_DIR/parse_stage19_kv_heatmap_summary.py" \
  "$RESULTS_DIR"/*/summary.log --csv > "$summary_csv" 2>/dev/null || \
  echo "[kairo] warning: summary aggregation failed"

echo "[kairo] complete: $RESULTS_DIR"
