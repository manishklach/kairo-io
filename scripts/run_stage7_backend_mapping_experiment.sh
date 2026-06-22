#!/usr/bin/env bash
#
# run_stage7_backend_mapping_experiment.sh
#
# Stage 7: generic NVMe backend mapping experiment harness.
#
# Runs five canonical backend mapping cases with structured results
# under results/stage7/<timestamp>/.
#
# Usage:
#   ./run_stage7_backend_mapping_experiment.sh <file-path> <block-device> [options]
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

FILE_PATH=""
BLOCK_DEVICE=""
DURATION=30
HINT_MODE="both"
SKIP_COUNTERS=false
DRY_RUN=false
RESULTS_DIR=""

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

if [[ -z "$FILE_PATH" ]]; then
  echo "ERROR: missing <file-path> argument" >&2
  exit 1
fi

if ! $SKIP_COUNTERS && [[ -z "$BLOCK_DEVICE" ]]; then
  echo "ERROR: missing <block-device> argument (required unless --skip-counters)" >&2
  exit 1
fi

BENCH="${BENCH_OVERRIDE:-}"
if [[ -z "$BENCH" ]]; then
  if [[ -x "$REPO_ROOT/kairo_bench" ]]; then
    BENCH="$REPO_ROOT/kairo_bench"
  elif [[ -x "$REPO_ROOT/bench/kairo_bench" ]]; then
    BENCH="$REPO_ROOT/bench/kairo_bench"
  else
    echo "ERROR: benchmark binary not found" >&2
    exit 1
  fi
fi

COLLECT="$SCRIPT_DIR/collect_kairo_counters.sh"
if ! $SKIP_COUNTERS && [[ ! -f "$COLLECT" ]]; then
  echo "ERROR: collect_kairo_counters.sh not found" >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="$REPO_ROOT/results/stage7/$TIMESTAMP"
fi

if ! $DRY_RUN; then
  mkdir -p "$RESULTS_DIR"
fi

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

  local cmd=("$BENCH" --file "$FILE_PATH" --runtime "$DURATION" --hint-mode "$HINT_MODE" "$@")
  printf '%s\n' "${cmd[*]}" > "$case_dir/command.txt"

  if ! $SKIP_COUNTERS && [[ -n "$BLOCK_DEVICE" ]]; then
    "$COLLECT" "$BLOCK_DEVICE" "$case_dir/counters-before" 2>/dev/null || \
      echo "[kairo] WARNING: before-counter collection failed for $case_name" >&2
  fi

  "${cmd[@]}" > "$case_dir/bench.log" 2>&1
  echo "bench_exit_code=$?" >> "$case_dir/bench.log"

  if ! $SKIP_COUNTERS && [[ -n "$BLOCK_DEVICE" ]]; then
    "$COLLECT" "$BLOCK_DEVICE" "$case_dir/counters-after" 2>/dev/null || \
      echo "[kairo] WARNING: after-counter collection failed for $case_name" >&2
  fi

  generate_summary "$case_name" "$case_dir"
}

read_counter() {
  local file="$1"
  if [[ -f "$file" ]]; then cat "$file"; else echo "NA"; fi
}

counter_delta() {
  local bf="$1" af="$2"
  if [[ ! -f "$bf" ]] || [[ ! -f "$af" ]]; then echo "NA"; return; fi
  local bv av
  bv="$(cat "$bf" 2>/dev/null || echo "NA")"
  av="$(cat "$af" 2>/dev/null || echo "NA")"
  bv="${bv//[[:space:]]/}"; av="${av//[[:space:]]/}"
  if [[ ! "$bv" =~ ^[0-9]+$ ]] || [[ ! "$av" =~ ^[0-9]+$ ]]; then echo "NA"; return; fi
  echo $((av - bv))
}

counter_delta_field() {
  local name="$1" case_dir="$2"
  local val
  val=$(counter_delta "$case_dir/counters-before/$name.txt" "$case_dir/counters-after/$name.txt")
  echo "${name}_delta=$val"
}

generate_summary() {
  local case_name="$1" case_dir="$2"
  local bl="$case_dir/bench.log" sf="$case_dir/summary.log"

  extract() {
    local key="$1"
    grep -E "^${key}=" "$bl" 2>/dev/null | head -1 | sed 's/^[^=]*=//' || echo ""
  }

  {
    echo "case=$case_name"
    printf 'command='; cat "$case_dir/command.txt" 2>/dev/null || echo ""
    echo "backend_mode=$(extract backend_mode)"
    echo "backend_class=$(extract backend_class)"
    echo "stream_id=$(extract stream_id)"
    echo "fdp_placement_id=$(extract fdp_placement_id)"
    echo "zone_hint=$(extract zone_hint)"
    echo "backend_noop_fallback=$(extract backend_noop_fallback)"
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

    if ! $SKIP_COUNTERS && [[ -n "$BLOCK_DEVICE" ]]; then
      for c in \
        kairo_backend_mapping_attempts \
        kairo_backend_noop_fallbacks \
        kairo_backend_stream_hints \
        kairo_backend_fdp_hints \
        kairo_backend_zns_hints \
        kairo_backend_short_lived \
        kairo_backend_session_local \
        kairo_backend_model_local \
        kairo_backend_recomputable \
        kairo_backend_persistent; do
        counter_delta_field "$c" "$case_dir"
      done
    fi
  } > "$sf"
}

all_counter_delta_names=(
  kairo_backend_mapping_attempts_delta
  kairo_backend_noop_fallbacks_delta
  kairo_backend_stream_hints_delta
  kairo_backend_fdp_hints_delta
  kairo_backend_zns_hints_delta
  kairo_backend_short_lived_delta
  kairo_backend_session_local_delta
  kairo_backend_model_local_delta
  kairo_backend_recomputable_delta
  kairo_backend_persistent_delta
)

csv_header="case,backend_mode,backend_class,stream_id,fdp_placement_id,zone_hint,backend_noop_fallback,models,sessions,cache_pools,placement_groups,lifetime,recompute_ok,semantic_mode,hint_mode,decode_p99_us,decode_p95_us,decode_avg_us,write_MBps,decode_read_MBps,prefetch_read_MBps,total_evictions"
for dname in "${all_counter_delta_names[@]}"; do
  csv_header="$csv_header,$dname"
done

collect_csv() {
  local csv="$RESULTS_DIR/summary.csv"
  echo "$csv_header" > "$csv"
  for case_dir in "$RESULTS_DIR"/*/; do
    local summary="$case_dir/summary.log"
    [[ -f "$summary" ]] || continue
    local row=""
    IFS=',' read -ra hdrs <<< "$csv_header"
    for h in "${hdrs[@]}"; do
      if [[ -n "$row" ]]; then row="$row,"; fi
      local val
      val="$(grep -E "^${h}=" "$summary" 2>/dev/null | head -1 | sed 's/^[^=]*=//')"
      row="${row}${val:-}"
    done
    echo "$row" >> "$csv"
  done
}

run_canonical_cases() {
  run_case "01-generic-short-lived" \
    --backend-mode generic \
    --mode mixed \
    --models 2 --sessions 4 --cache-pools 2 --placement-groups 2 \
    --lifetime short

  run_case "02-generic-session-local" \
    --backend-mode generic \
    --mode multisession \
    --models 1 --sessions 8 --cache-pools 2 --placement-groups 4 \
    --lifetime session

  run_case "03-streams-model-local" \
    --backend-mode streams \
    --mode mixed \
    --models 4 --sessions 8 --cache-pools 4 --placement-groups 8 \
    --lifetime model

  run_case "04-fdp-cache-pool" \
    --backend-mode fdp \
    --mode mixed \
    --models 4 --sessions 8 --cache-pools 4 --placement-groups 4 \
    --lifetime model

  run_case "05-zns-short-lived" \
    --backend-mode zns \
    --mode eviction-pressure \
    --semantic-mode ephemeral-recomputable --recompute-ok \
    --models 2 --sessions 8 --cache-pools 2 --placement-groups 4 \
    --lifetime short
}

echo "========================================"
echo " Stage 7: Generic Backend Mapping"
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
echo " Stage 7 experiment complete."
echo " Results: $RESULTS_DIR"
echo " CSV:     $RESULTS_DIR/summary.csv"
echo "========================================"
