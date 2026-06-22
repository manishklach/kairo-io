#!/usr/bin/env bash
#
# run_stage6_placement_experiment.sh
#
# Stage 6.5: placement experiment harness hardening.
#
# Runs five canonical Stage 6 placement/lifetime benchmark cases and
# collects structured results under results/stage6/<timestamp>/.
#
# Usage:
#   ./run_stage6_placement_experiment.sh <file-path> <block-device> [options]
#
# Options:
#   --duration SEC          Per-case runtime in seconds (default: 30)
#   --bench PATH            Benchmark binary path
#   --results-dir PATH      Override output directory
#   --hint-mode MODE        ioprio|rwf|both (default: both)
#   --skip-counters         Skip sysfs counter collection
#   --dry-run               Print commands without executing
#   --help                  Show this help

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# ---- defaults ----
FILE_PATH=""
BLOCK_DEVICE=""
DURATION=30
HINT_MODE="both"
SKIP_COUNTERS=false
DRY_RUN=false
RESULTS_DIR=""

# ---- arg parsing ----
usage() {
  sed -n 's/^# \?//p' "$0" | head -40
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --bench) BENCH_OVERRIDE="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --hint-mode) HINT_MODE="$2"; shift 2 ;;
    --skip-counters) SKIP_COUNTERS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage ;;
    --*) echo "unknown option: $1"; exit 1 ;;
    *)
      if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH="$1"
      elif [[ -z "$BLOCK_DEVICE" ]]; then
        BLOCK_DEVICE="$1"
      else
        echo "unexpected argument: $1"; exit 1
      fi
      shift ;;
  esac
done

# ---- validate arguments ----
if [[ -z "$FILE_PATH" ]]; then
  echo "ERROR: missing <file-path> argument" >&2
  echo "Usage: $0 <file-path> <block-device> [options]" >&2
  exit 1
fi

if ! $SKIP_COUNTERS && [[ -z "$BLOCK_DEVICE" ]]; then
  echo "ERROR: missing <block-device> argument (required unless --skip-counters)" >&2
  exit 1
fi

# ---- locate benchmark ----
if [[ -n "${BENCH_OVERRIDE:-}" ]]; then
  BENCH="$BENCH_OVERRIDE"
elif [[ -x "$REPO_ROOT/kairo_bench" ]]; then
  BENCH="$REPO_ROOT/kairo_bench"
elif [[ -x "$REPO_ROOT/bench/kairo_bench" ]]; then
  BENCH="$REPO_ROOT/bench/kairo_bench"
else
  echo "ERROR: benchmark binary not found (tried ./kairo_bench, bench/kairo_bench)" >&2
  echo "Build with: make" >&2
  exit 1
fi

# ---- locate counter collector ----
COLLECT_COUNTERS="$SCRIPT_DIR/collect_kairo_counters.sh"
if ! $SKIP_COUNTERS && [[ ! -f "$COLLECT_COUNTERS" ]]; then
  echo "ERROR: collect_kairo_counters.sh not found at $COLLECT_COUNTERS" >&2
  exit 1
fi

# ---- setup results directory ----
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="$REPO_ROOT/results/stage6/$TIMESTAMP"
fi

if $DRY_RUN; then
  echo "[dry-run] results dir: $RESULTS_DIR"
else
  mkdir -p "$RESULTS_DIR"
fi

# ---- run_metadata.log ----
write_metadata() {
  local meta="$RESULTS_DIR/run_metadata.log"
  {
    echo "timestamp=$(date --iso-8601=seconds)"
    echo "repo_root=$REPO_ROOT"
    echo "bench_path=$BENCH"
    echo "file_path=$FILE_PATH"
    echo "block_device=${BLOCK_DEVICE:-none}"
    echo "duration=$DURATION"
    echo "hint_mode=$HINT_MODE"
    echo "uname=$(uname -r 2>/dev/null || echo unknown)"
    if git rev-parse HEAD &>/dev/null; then
      echo "repo_commit=$(git rev-parse HEAD)"
      echo "repo_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    fi
  } | tee "$meta"
}

if ! $DRY_RUN; then
  write_metadata
fi

# ---- helper: run one case ----
# Stores results in $CASE_DIR, writes command.txt, bench.log, summary.log
run_case() {
  local case_name="$1"
  shift
  local case_dir="$RESULTS_DIR/$case_name"

  if $DRY_RUN; then
    echo "[dry-run] case: $case_name"
    echo "[dry-run]   dir: $case_dir"
    echo "[dry-run]   cmd: $BENCH --file \"$FILE_PATH\" --runtime \"$DURATION\" --hint-mode \"$HINT_MODE\" $*"
    return
  fi

  mkdir -p "$case_dir"

  # Build command
  local cmd=("$BENCH" --file "$FILE_PATH" --runtime "$DURATION" --hint-mode "$HINT_MODE" "$@")

  # Write command.txt
  printf '%s\n' "${cmd[*]}" > "$case_dir/command.txt"

  # Collect counters before
  if ! $SKIP_COUNTERS && [[ -n "$BLOCK_DEVICE" ]]; then
    "$COLLECT_COUNTERS" "$BLOCK_DEVICE" "$case_dir/counters-before" 2>/dev/null || \
      echo "[kairo] WARNING: counter collection before $case_name failed (counters may be missing)" >&2
  fi

  # Run benchmark
  "${cmd[@]}" > "$case_dir/bench.log" 2>&1
  local bench_exit=$?
  echo "bench_exit_code=$bench_exit" >> "$case_dir/bench.log"

  # Collect counters after
  if ! $SKIP_COUNTERS && [[ -n "$BLOCK_DEVICE" ]]; then
    "$COLLECT_COUNTERS" "$BLOCK_DEVICE" "$case_dir/counters-after" 2>/dev/null || \
      echo "[kairo] WARNING: counter collection after $case_name failed" >&2
  fi

  # Generate summary.log
  generate_summary "$case_name" "$case_dir"
}

# ---- counter delta helpers ----
read_counter() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    echo "NA"
  fi
}

counter_delta() {
  local before_file="$1"
  local after_file="$2"

  if [[ ! -f "$before_file" ]] || [[ ! -f "$after_file" ]]; then
    echo "NA"
    return
  fi

  local before after
  before="$(cat "$before_file" 2>/dev/null || echo "NA")"
  after="$(cat "$after_file" 2>/dev/null || echo "NA")"

  if [[ "$before" == "NA" ]] || [[ "$after" == "NA" ]]; then
    echo "NA"
    return
  fi

  # Strip whitespace, convert to integer if possible
  before="${before//[[:space:]]/}"
  after="${after//[[:space:]]/}"

  if [[ ! "$before" =~ ^[0-9]+$ ]] || [[ ! "$after" =~ ^[0-9]+$ ]]; then
    echo "NA"
    return
  fi

  echo $((after - before))
}

counter_delta_field() {
  local name="$1"
  local case_dir="$2"
  local val
  val=$(counter_delta "$case_dir/counters-before/$name.txt" "$case_dir/counters-after/$name.txt")
  echo "${name}_delta=$val"
}

# ---- summary generation ----
generate_summary() {
  local case_name="$1"
  local case_dir="$2"
  local bench_log="$case_dir/bench.log"
  local summary_file="$case_dir/summary.log"

  extract() {
    local key="$1"
    grep -E "^${key}=" "$bench_log" 2>/dev/null | head -1 | sed 's/^[^=]*=//' || echo ""
  }

  {
    echo "case=$case_name"
    printf 'command='
    cat "$case_dir/command.txt" 2>/dev/null || echo ""

    echo "models=$(extract models)"
    echo "sessions=$(extract sessions)"
    echo "cache_pools=$(extract cache_pools)"
    echo "placement_groups=$(extract placement_groups)"
    echo "lifetime=$(extract lifetime)"
    echo "recompute_ok=$(extract recompute_ok)"
    echo "semantic_mode=$(extract semantic_mode)"
    echo "hint_mode=$(extract hint_mode)"

    echo "decode_p99_us=$(extract decode_p99_us)"
    echo "decode_p95_us=$(extract decode_p95_us)"
    echo "decode_avg_us=$(extract decode_avg_us)"
    echo "write_MBps=$(extract write_MBps)"
    echo "decode_read_MBps=$(extract decode_read_MBps)"
    echo "prefetch_read_MBps=$(extract prefetch_read_MBps)"
    echo "total_evictions=$(extract evict_total_ops)"

    # Counter deltas
    if ! $SKIP_COUNTERS && [[ -n "$BLOCK_DEVICE" ]]; then
      counter_delta_field "kairo_model_tagged_requests" "$case_dir"
      counter_delta_field "kairo_session_tagged_requests" "$case_dir"
      counter_delta_field "kairo_cache_pool_tagged_requests" "$case_dir"
      counter_delta_field "kairo_recompute_ok_requests" "$case_dir"
      counter_delta_field "kairo_placement_hints" "$case_dir"
      counter_delta_field "kairo_has_model_id_count" "$case_dir"
      counter_delta_field "kairo_has_session_id_count" "$case_dir"
      counter_delta_field "kairo_has_cache_pool_count" "$case_dir"
      counter_delta_field "kairo_lifetime_short_count" "$case_dir"
      counter_delta_field "kairo_lifetime_session_count" "$case_dir"
      counter_delta_field "kairo_lifetime_model_count" "$case_dir"
      counter_delta_field "kairo_lifetime_persistent_count" "$case_dir"
    fi
  } > "$summary_file"
}

# ---- union of all counter names for CSV header ----
all_counter_delta_names=(
  "kairo_model_tagged_requests_delta"
  "kairo_session_tagged_requests_delta"
  "kairo_cache_pool_tagged_requests_delta"
  "kairo_recompute_ok_requests_delta"
  "kairo_placement_hints_delta"
  "kairo_has_model_id_count_delta"
  "kairo_has_session_id_count_delta"
  "kairo_has_cache_pool_count_delta"
  "kairo_lifetime_short_count_delta"
  "kairo_lifetime_session_count_delta"
  "kairo_lifetime_model_count_delta"
  "kairo_lifetime_persistent_count_delta"
)

# ---- CSV header fields (matching parse_stage6_placement_summary.py ordering) ----
csv_header="case,models,sessions,cache_pools,placement_groups,lifetime,recompute_ok,semantic_mode,hint_mode,decode_p99_us,decode_p95_us,decode_avg_us,write_MBps,decode_read_MBps,prefetch_read_MBps,total_evictions"
for dname in "${all_counter_delta_names[@]}"; do
  csv_header="$csv_header,$dname"
done

# ---- collect summary.csv ----
collect_csv() {
  local csv_file="$RESULTS_DIR/summary.csv"
  echo "$csv_header" > "$csv_file"

  for case_dir in "$RESULTS_DIR"/*/; do
    local summary="$case_dir/summary.log"
    [[ -f "$summary" ]] || continue

    local case_name
    case_name="$(basename "$case_dir")"

    local row=""
    # Build row from header fields
    IFS=',' read -ra hdrs <<< "$csv_header"
    for h in "${hdrs[@]}"; do
      if [[ -n "$row" ]]; then
        row="$row,"
      fi
      # Extract value from summary.log
      local val
      val="$(grep -E "^${h}=" "$summary" 2>/dev/null | head -1 | sed 's/^[^=]*=//')"
      row="${row}${val:-}"
    done

    echo "$row" >> "$csv_file"
  done
}

# ---- canonical cases ----
run_canonical_cases() {
  # Case 1: single-model-single-session
  run_case "01-single-model-single-session" \
    --mode mixed \
    --models 1 --sessions 1 --cache-pools 1 --placement-groups 1 \
    --lifetime session

  # Case 2: multi-session-single-model
  run_case "02-multi-session-single-model" \
    --mode multisession \
    --models 1 --sessions 8 --cache-pools 1 --placement-groups 4 \
    --lifetime session

  # Case 3: multi-model-multi-session
  run_case "03-multi-model-multi-session" \
    --mode multisession \
    --models 4 --sessions 16 --cache-pools 4 --placement-groups 8 \
    --lifetime model

  # Case 4: multi-cache-pool
  run_case "04-multi-cache-pool" \
    --mode mixed \
    --models 4 --sessions 8 --cache-pools 4 --placement-groups 4 \
    --lifetime short

  # Case 5: recomputable-session-cache
  run_case "05-recomputable-session-cache" \
    --mode eviction-pressure \
    --semantic-mode ephemeral-recomputable --recompute-ok \
    --models 2 --sessions 8 --cache-pools 2 --placement-groups 4 \
    --lifetime short
}

# ---- main ----
echo "========================================"
echo " Stage 6.5: Placement Experiment Harness"
echo "========================================"
echo "Benchmark:   $BENCH"
echo "File:        $FILE_PATH"
echo "Block dev:   ${BLOCK_DEVICE:-<skipped>}"
echo "Duration:    ${DURATION}s"
echo "Hint mode:   $HINT_MODE"
echo "Results:     $RESULTS_DIR"
$DRY_RUN && echo "*** DRY RUN ***"
echo ""

if $DRY_RUN; then
  run_canonical_cases
  echo ""
  echo "[dry-run] Would generate summary.csv at $RESULTS_DIR/summary.csv"
  exit 0
fi

run_canonical_cases

collect_csv

echo "========================================"
echo " Stage 6.5 experiment complete."
echo " Results: $RESULTS_DIR"
echo " CSV:     $RESULTS_DIR/summary.csv"
echo "========================================"
