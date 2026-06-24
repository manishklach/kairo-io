#!/usr/bin/env bash
#
# run_stage11_foundation_trace_experiment.sh
#
# Stage 11: foundation tracepoint experiment harness.
#
# Detects whether Kairo tracepoints are available on the running kernel,
# runs a mixed benchmark with optional ftrace capture, and saves structured
# results under results/stage11/<timestamp>/.
#
# Usage:
#   ./run_stage11_foundation_trace_experiment.sh <file-path> <block-device> [options]
#
# Options:
#   --duration SEC          Per-case runtime in seconds (default: 30)
#   --bench PATH            Benchmark binary path
#   --results-dir PATH      Override output directory
#   --trace-mode MODE       ftrace|none (default: none)
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
TRACE_MODE="none"
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
    --trace-mode) TRACE_MODE="$2"; shift 2 ;;
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

detect_tracepoints() {
  local trace_dir="/sys/kernel/tracing/events/kairo"
  if [[ -d "$trace_dir" ]]; then
    printf 'tracepoints_available=true\n'
    printf 'trace_dir=%s\n' "$trace_dir"
    # Check each foundation tracepoint
    for tp in kairo_request_classified kairo_decode_dispatch \
              kairo_prefetch_dispatch kairo_write_demoted; do
      if [[ -d "$trace_dir/$tp" ]]; then
        printf 'tracepoint_%s=available\n' "$tp"
      else
        printf 'tracepoint_%s=missing\n' "$tp"
      fi
    done
  else
    printf 'tracepoints_available=false\n'
  fi
}

enable_tracepoints() {
  local trace_dir="/sys/kernel/tracing/events/kairo"
  if [[ ! -d "$trace_dir" ]]; then
    return 1
  fi
  for tp in kairo_request_classified kairo_decode_dispatch \
            kairo_prefetch_dispatch kairo_write_demoted; do
    if [[ -d "$trace_dir/$tp" ]]; then
      dry_cmd sh -c "echo 1 > '$trace_dir/$tp/enable' 2>/dev/null || true"
    fi
  done
}

disable_tracepoints() {
  local trace_dir="/sys/kernel/tracing/events/kairo"
  if [[ ! -d "$trace_dir" ]]; then
    return
  fi
  for tp in kairo_request_classified kairo_decode_dispatch \
            kairo_prefetch_dispatch kairo_write_demoted; do
    if [[ -d "$trace_dir/$tp" ]]; then
      dry_cmd sh -c "echo 0 > '$trace_dir/$tp/enable' 2>/dev/null || true"
    fi
  done
}

# ---- setup ----
if [[ -z "$RESULTS_DIR" ]]; then
  RESULTS_DIR="$REPO_ROOT/results/stage11/$(date -u +%Y%m%d-%H%M%S)"
fi
mkdir -p "$RESULTS_DIR"

dry_cmd cp "$0" "$RESULTS_DIR/"

echo "[stage11] Stage 11 Foundation Trace Experiment"
echo "[stage11] File: $FILE_PATH"
echo "[stage11] Device: $BLOCK_DEVICE"
echo "[stage11] Duration: ${DURATION}s"
echo "[stage11] Trace mode: $TRACE_MODE"
echo "[stage11] Results: $RESULTS_DIR"

# ---- detect tracepoints ----
echo "[stage11] Detecting Kairo tracepoints..."
trace_available_log="$RESULTS_DIR/trace_available.log"
detect_tracepoints | dry_cmd tee "$trace_available_log"

# ---- collect pre-run counters ----
if [[ "$SKIP_COUNTERS" != true ]]; then
  collect_counters "before" "before"
fi

# ---- enable tracepoints (ftrace mode) ----
if [[ "$TRACE_MODE" == "ftrace" ]]; then
  echo "[stage11] Enabling foundation tracepoints..."
  enable_tracepoints || \
    echo "[stage11] WARNING: could not enable tracepoints (unpatched kernel?)"
fi

# ---- run benchmark ----
echo "[stage11] Running benchmark..."
bench_cmd="$(bench_exe) --duration $DURATION --file $FILE_PATH --device $BLOCK_DEVICE"
bench_log="$RESULTS_DIR/benchmark.log"

dry_cmd sh -c "$bench_cmd 2>&1" > "$bench_log" || true

# ---- collect trace log (ftrace mode) ----
if [[ "$TRACE_MODE" == "ftrace" ]]; then
  trace_dir="$RESULTS_DIR/trace"
  dry_cmd mkdir -p "$trace_dir"
  dry_cmd sh -c "cat /sys/kernel/tracing/trace > '$trace_dir/kairo_foundation_trace.log' 2>/dev/null || true"

  # Disable tracepoints after capture
  disable_tracepoints
fi

# ---- collect post-run counters ----
if [[ "$SKIP_COUNTERS" != true ]]; then
  collect_counters "after" "after"
fi

# ---- write summary ----
echo "[stage11] Writing summary..."
summary_log="$RESULTS_DIR/summary.log"
{
  echo "stage11_foundation_trace_experiment"
  echo "duration=$DURATION"
  echo "trace_mode=$TRACE_MODE"
  echo "file=$FILE_PATH"
  echo "device=$BLOCK_DEVICE"
  if [[ -f "$trace_available_log" ]]; then
    cat "$trace_available_log"
  fi
} > "$summary_log"

# ---- generate summary CSV ----
summary_csv="$RESULTS_DIR/summary.csv"
printf "case,tracepoints_available,decode_dispatches,prefetch_dispatches,normal_dispatches,starvation_escapes\n" > "$summary_csv"

decode_val="NA"
prefetch_val="NA"
normal_val="NA"
starvation_val="NA"

if [[ "$SKIP_COUNTERS" != true ]]; then
  after_dir="$RESULTS_DIR/after/counters-after"
  if [[ -d "$after_dir" ]]; then
    for f in "$after_dir"/*; do
      name="$(basename "$f")"
      val="$(cat "$f" 2>/dev/null || echo 'NA')"
      case "$name" in
        kairo_decode_dispatches) decode_val="$val" ;;
        kairo_prefetch_dispatches) prefetch_val="$val" ;;
        kairo_normal_dispatches) normal_val="$val" ;;
        kairo_starvation_escapes) starvation_val="$val" ;;
      esac
    done
  fi
fi

tp_avail="false"
if [[ -f "$trace_available_log" ]] && grep -q "tracepoints_available=true" "$trace_available_log"; then
  tp_avail="true"
fi

printf "foundation-trace,%s,%s,%s,%s,%s\n" \
  "$tp_avail" "$decode_val" "$prefetch_val" "$normal_val" "$starvation_val" >> "$summary_csv"

echo "[stage11] Summary: $summary_csv"
echo "[stage11] Done."
