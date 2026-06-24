#!/usr/bin/env bash
#
# run_stage12_fairness_experiment.sh
#
# Stage 12: per-model / per-session fairness experiment harness.
#
# Runs a mixed benchmark with multi-session and noisy-session variants
# to exercise the fairness scheduling concept. Saves structured results
# under results/stage12/<timestamp>/.
#
# Usage:
#   ./run_stage12_fairness_experiment.sh <file-path> <block-device> [options]
#
# Options:
#   --duration SEC          Per-case runtime in seconds (default: 30)
#   --bench PATH            Benchmark binary path
#   --results-dir PATH      Override output directory
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
SKIP_COUNTERS=false
DRY_RUN=false
RESULTS_DIR=""

# ---- arg parsing ----
usage() {
  sed -n 's/^# \?//p' "$0" | head -40
  exit 0
}

resolve_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$PWD" "$path"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --bench) BENCH_PATH="$2"; shift 2 ;;
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --skip-counters) SKIP_COUNTERS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage ;;
    --*) echo "Unknown option: $1"; usage ;;
    *)
      if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH="$(resolve_path "$1")"
      elif [[ -z "$BLOCK_DEVICE" ]]; then
        BLOCK_DEVICE="$1"
      else
        echo "Unexpected argument: $1"; usage
      fi
      shift
      ;;
  esac
done

if [[ -z "$FILE_PATH" || -z "$BLOCK_DEVICE" ]]; then
  echo "Usage: $0 <file-path> <block-device> [options]"
  exit 1
fi

# ---- helper functions ----
dry_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[DRY_RUN] %s\n' "$*"
  else
    "$@"
  fi
}

COUNTER_NAMES=(
  kairo_decode_dispatches
  kairo_prefetch_dispatches
  kairo_prefill_dispatches
  kairo_evict_dispatches
  kairo_normal_dispatches
  kairo_starvation_escapes
  kairo_fairness_refills
  kairo_fairness_model_throttles
  kairo_fairness_session_throttles
  kairo_noisy_session_events
  kairo_protected_decode_dispatches
  kairo_prefetch_fairness_throttles
  kairo_write_fairness_demotions
)

collect_counters() {
  local label="$1"
  local sysfs_dir="/sys/block/$BLOCK_DEVICE/mq-deadline"
  local outdir="$RESULTS_DIR/$label/counters-before"
  if [[ "$2" == "after" ]]; then
    outdir="$RESULTS_DIR/$label/counters-after"
  fi
  dry_cmd mkdir -p "$outdir"
  for c in "${COUNTER_NAMES[@]}"; do
    local path="$sysfs_dir/$c"
    if [[ -r "$path" ]]; then
      dry_cmd sh -c "cat '$path' > '$outdir/$c'"
    fi
  done
}

bench_exe() {
  if [[ -n "${BENCH_PATH:-}" ]]; then
    printf '%s\n' "$BENCH_PATH"
  elif [[ -x "$REPO_ROOT/build/bench/kairo_bench" ]]; then
    printf '%s\n' "$REPO_ROOT/build/bench/kairo_bench"
  elif [[ -x "$REPO_ROOT/bench/kairo_bench" ]]; then
    printf '%s\n' "$REPO_ROOT/bench/kairo_bench"
  else
    printf '%s\n' "kairo_bench"
  fi
}

# ---- experiment cases ----
CASES=(
  "01-balanced-multisession"
  "02-noisy-session-no-fairness"
  "03-noisy-session-fairness-observe"
  "04-noisy-session-fairness-enabled"
  "05-noisy-model-fairness-enabled"
)

run_case() {
  local case="$1"
  local bench_args="$2"
  local fairness_args="$3"

  local case_dir="$RESULTS_DIR/$case"
  dry_cmd mkdir -p "$case_dir"

  echo "[stage12] Running case: $case"

  dry_cmd cp "$0" "$case_dir/command.txt"

  # Collect pre-run counters
  if [[ "$SKIP_COUNTERS" != true ]]; then
    collect_counters "$case" "before"
  fi

  # Run benchmark
  local bench_cmd
  bench_cmd="$(bench_exe) --duration $DURATION --file $FILE_PATH --device $BLOCK_DEVICE $bench_args"
  local bench_log="$case_dir/bench.log"
  echo "[stage12]   $bench_cmd"
  dry_cmd sh -c "$bench_cmd 2>&1" > "$bench_log" || true

  # Collect post-run counters
  if [[ "$SKIP_COUNTERS" != true ]]; then
    collect_counters "$case" "after"
  fi

  # Write summary.log
  local summary_log="$case_dir/summary.log"
  {
    echo "stage12_fairness_experiment"
    echo "case=$case"
    echo "duration=$DURATION"
    echo "file=$FILE_PATH"
    echo "device=$BLOCK_DEVICE"
    echo "fairness_mode=$fairness_args"
  } > "$summary_log"

  # Extract bench metrics
  if [[ -f "$bench_log" ]]; then
    grep -E "^(decode_avg_us|decode_p95_us|decode_p99_us|write_MBps|prefetch_read_MBps|models=|sessions=)=" \
      "$bench_log" >> "$summary_log" 2>/dev/null || true
  fi

  # Collect counter deltas
  if [[ "$SKIP_COUNTERS" != true ]]; then
    {
      echo "--- counter deltas ---"
      local before_dir="$case_dir/counters-before"
      local after_dir="$case_dir/counters-after"
      if [[ -d "$before_dir" && -d "$after_dir" ]]; then
        for c in "${COUNTER_NAMES[@]}"; do
          local bf="$before_dir/$c"
          local af="$after_dir/$c"
          local before_val=0
          local after_val=0
          if [[ -r "$bf" ]]; then
            before_val=$(cat "$bf" 2>/dev/null || echo 0)
          fi
          if [[ -r "$af" ]]; then
            after_val=$(cat "$af" 2>/dev/null || echo 0)
          fi
          local delta
          delta=$((after_val - before_val))
          echo "${c}_delta=$delta"
        done
      fi
    } >> "$summary_log"
  fi
}

# ---- setup ----
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="$REPO_ROOT/results/stage12/$(date -u +%Y%m%d-%H%M%S)"
fi
mkdir -p "$RESULTS_DIR"

echo "[stage12] Stage 12 Per-Model/Per-Session Fairness Experiment"
echo "[stage12] File: $FILE_PATH"
echo "[stage12] Device: $BLOCK_DEVICE"
echo "[stage12] Duration: ${DURATION}s"
echo "[stage12] Results: $RESULTS_DIR"

# Run each case
run_case "01-balanced-multisession" \
  "--mode multisession --sessions 4 --models 2" \
  "disabled"

run_case "02-noisy-session-no-fairness" \
  "--mode multisession --sessions 4 --models 2 --noisy-session 1 --noisy-multiplier 5" \
  "disabled"

run_case "03-noisy-session-fairness-observe" \
  "--mode multisession --sessions 4 --models 2 --noisy-session 1 --noisy-multiplier 5" \
  "observe"

run_case "04-noisy-session-fairness-enabled" \
  "--mode multisession --sessions 4 --models 2 --noisy-session 1 --noisy-multiplier 5" \
  "enabled"

run_case "05-noisy-model-fairness-enabled" \
  "--mode multisession --sessions 4 --models 4 --noisy-model 1 --noisy-multiplier 5" \
  "enabled"

# ---- write summary CSV ----
echo "[stage12] Writing summary CSV..."
summary_csv="$RESULTS_DIR/summary.csv"
{
  printf "case,models,sessions,noisy_model,noisy_session,noisy_multiplier,"
  printf "decode_p99_us,decode_p95_us,decode_avg_us,"
  printf "write_MBps,prefetch_read_MBps,"
  printf "kairo_fairness_refills_delta,"
  printf "kairo_fairness_model_throttles_delta,"
  printf "kairo_fairness_session_throttles_delta,"
  printf "kairo_noisy_session_events_delta,"
  printf "kairo_protected_decode_dispatches_delta,"
  printf "kairo_prefetch_fairness_throttles_delta,"
  printf "kairo_write_fairness_demotions_delta\n"

  for case in "${CASES[@]}"; do
    sl="$RESULTS_DIR/$case/summary.log"
    if [[ ! -f "$sl" ]]; then
      continue
    fi

    # Extract values from summary.log
    models="$(grep -E "^models=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    sessions="$(grep -E "^sessions=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    decode_p99="$(grep -E "^decode_p99_us=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    decode_p95="$(grep -E "^decode_p95_us=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    decode_avg="$(grep -E "^decode_avg_us=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    write_mbps="$(grep -E "^write_MBps=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    prefetch_mbps="$(grep -E "^prefetch_read_MBps=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"

    # Counter deltas
    refills_delta="$(grep -E "^kairo_fairness_refills_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    model_thr_delta="$(grep -E "^kairo_fairness_model_throttles_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    session_thr_delta="$(grep -E "^kairo_fairness_session_throttles_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    noisy_events_delta="$(grep -E "^kairo_noisy_session_events_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    protected_delta="$(grep -E "^kairo_protected_decode_dispatches_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    prefetch_thr_delta="$(grep -E "^kairo_prefetch_fairness_throttles_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"
    write_dem_delta="$(grep -E "^kairo_write_fairness_demotions_delta=" "$sl" 2>/dev/null | head -1 | cut -d= -f2)"

    # Defaults
    : "${models:=NA}" "${sessions:=NA}" "${decode_p99:=NA}" "${decode_p95:=NA}"
    : "${decode_avg:=NA}" "${write_mbps:=NA}" "${prefetch_mbps:=NA}"
    : "${refills_delta:=NA}" "${model_thr_delta:=NA}" "${session_thr_delta:=NA}"
    : "${noisy_events_delta:=NA}" "${protected_delta:=NA}"
    : "${prefetch_thr_delta:=NA}" "${write_dem_delta:=NA}"

    # Determine noisy params from case name
    noisy_model="0"
    noisy_session="0"
    noisy_multiplier="0"
    case "$case" in
      02-noisy-session-*) noisy_session=1; noisy_multiplier=5 ;;
      03-noisy-session-*) noisy_session=1; noisy_multiplier=5 ;;
      04-noisy-session-*) noisy_session=1; noisy_multiplier=5 ;;
      05-noisy-model-*) noisy_model=1; noisy_multiplier=5 ;;
    esac

    printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n" \
      "$case" \
      "$models" "$sessions" \
      "$noisy_model" "$noisy_session" "$noisy_multiplier" \
      "$decode_p99" "$decode_p95" "$decode_avg" \
      "$write_mbps" "$prefetch_mbps" \
      "$refills_delta" "$model_thr_delta" "$session_thr_delta" \
      "$noisy_events_delta" "$protected_delta" \
      "$prefetch_thr_delta" "$write_dem_delta"
  done
} > "$summary_csv"

echo "[stage12] Summary: $summary_csv"
echo "[stage12] Done."
