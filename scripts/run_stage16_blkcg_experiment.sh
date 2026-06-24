#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/stage16/$TIMESTAMP"
BENCH="$REPO_ROOT/kairo_bench"
DURATION=10
SKIP_COUNTERS=false
DRY_RUN=false
HINT_MODE="ioprio"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_stage16_blkcg_experiment.sh <file-path> <block-device> [options]

Options:
  --duration SEC           default 10
  --bench PATH             default <repo>/kairo_bench
  --results-dir PATH       default results/stage16/<timestamp>
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
  "01-single-tenant-production:decode-only:4:0:0:0"
  "02-production-vs-batch:mixed:3:1:1:0"
  "03-production-vs-eviction:mixed:3:0:1:1"
  "04-mixed-tenants:mixed:2:2:2:1"
  "05-background-pressure:mixed:1:4:4:4"
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
  local tenants
  local tenant_mode
  local models=1
  local sessions=1
  local noisy_model=0
  local noisy_session=0
  local noisy_multiplier=1

  mkdir -p "$case_dir"
  mkdir -p "$case_dir/counters-before" "$case_dir/counters-after"

  collect_counters "$case_label/counters-before"

  case "$case_label" in
    01*)
      tenants=1
      tenant_mode="production"
      ;;
    02*)
      tenants=2
      tenant_mode="mixed"
      models=2
      sessions=2
      noisy_model=1
      noisy_multiplier=6
      ;;
    03*)
      tenants=2
      tenant_mode="mixed"
      models=2
      sessions=2
      noisy_session=1
      noisy_multiplier=6
      ;;
    04*)
      tenants=4
      tenant_mode="mixed"
      models=4
      sessions=4
      noisy_model=2
      noisy_session=3
      noisy_multiplier=8
      ;;
    05*)
      tenants=2
      tenant_mode="background"
      models=2
      sessions=4
      noisy_model=1
      noisy_session=1
      noisy_multiplier=12
      ;;
  esac

  local bench_cmd
  bench_cmd=("$BENCH" --file "$FILE_PATH" --runtime "$DURATION" --mode "$mode" \
    --hint-mode "$HINT_MODE" \
    --models "$models" \
    --sessions "$sessions" \
    --decode-threads "$decode_threads" \
    --prefetch-threads "$prefetch_threads" \
    --write-threads "$write_threads" \
    --evict-threads "$evict_threads")

  if (( noisy_model > 0 )); then
    bench_cmd+=(--noisy-model "$noisy_model" --noisy-multiplier "$noisy_multiplier")
  fi
  if (( noisy_session > 0 )); then
    bench_cmd+=(--noisy-session "$noisy_session" --noisy-multiplier "$noisy_multiplier")
  fi

  local summary_file="$case_dir/summary.log"
  : > "$case_dir/command.txt"
  printf '%q ' "${bench_cmd[@]}" >> "$case_dir/command.txt"
  printf '\n' >> "$case_dir/command.txt"

  if $DRY_RUN; then
    printf '%s\n' "${bench_cmd[*]}" > "$summary_file"
    cat >> "$summary_file" <<DRYEOF
decode_p99_us=0
decode_p95_us=0
decode_avg_us=0
write_MBps=0
prefetch_read_MBps=0
models=${models}
sessions=${sessions}
tenant_id=1
tenants=${tenants}
tenant_mode=${tenant_mode}
noisy_model=${noisy_model}
noisy_session=${noisy_session}
noisy_multiplier=${noisy_multiplier}
kairo_blkg_decode_dispatches=0
kairo_blkg_prefetch_dispatches=0
kairo_blkg_prefill_writes=0
kairo_blkg_evictions=0
kairo_blkg_throttled_prefetches=0
kairo_blkg_demoted_writes=0
kairo_blkg_latency_violations=0
DRYEOF
  else
    "${bench_cmd[@]}" > "$summary_file" 2>&1 || true
  fi

  collect_counters "$case_label/counters-after"

  {
    echo "case=$case_label"
    echo "mode=$mode"
    echo "models=$models"
    echo "sessions=$sessions"
    echo "tenant_id=1"
    echo "tenants=$tenants"
    echo "tenant_mode=$tenant_mode"
    echo "noisy_model=$noisy_model"
    echo "noisy_session=$noisy_session"
    echo "noisy_multiplier=$noisy_multiplier"
  } >> "$summary_file"
}

echo "[kairo] Stage 16 experiment: $TIMESTAMP"
echo "[kairo] results: $RESULTS_DIR"

: > "$summary_csv"

for entry in "${cases[@]}"; do
  IFS=':' read -r label mode dt pt wt et <<< "$entry"
  echo "[kairo] case $label ($mode, decode=$dt prefetch=$pt write=$wt evict=$et)"
  run_case "$label" "$mode" "$dt" "$pt" "$wt" "$et"
done

echo "[kairo] generating aggregate summary..."
python3 "$SCRIPT_DIR/parse_stage16_blkcg_summary.py" \
  "$RESULTS_DIR"/*/summary.log --csv > "$summary_csv" 2>/dev/null || \
  echo "[kairo] warning: summary aggregation failed"

echo "[kairo] complete: $RESULTS_DIR"
