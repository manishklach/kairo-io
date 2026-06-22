#!/usr/bin/env bash
# Stage 8: Run Kairo trace observability experiment.
#
# Usage:
#   ./scripts/run_stage8_trace_experiment.sh <file-path> <block-device> [options]
#
# Options:
#   --duration SEC        Benchmark duration in seconds (default: 30)
#   --bench PATH          Path to kairo_bench binary (default: ./kairo_bench)
#   --results-dir PATH    Custom results directory (default: results/stage8)
#   --hint-mode MODE      Hint mode: ioprio|rwf|both (default: ioprio)
#   --trace-mode MODE     Trace mode: ftrace|bpftrace|none (default: auto)
#   --skip-counters       Skip counter collection
#   --dry-run             Print commands without executing
#   --help                Show this message

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BENCH_DEFAULT="$REPO_ROOT/kairo_bench"
RESULTS_BASE="$REPO_ROOT/results/stage8"
TIMESTAMP="$(date +%Y%m%dT%H%M%S)"
RESULTS_DIR=""

FILE_PATH=""
BLOCK_DEV=""
DURATION=30
BENCH="$BENCH_DEFAULT"
HINT_MODE="ioprio"
TRACE_MODE="auto"
SKIP_COUNTERS=false
DRY_RUN=false

fail() {
  echo "[stage8] ERROR: $*" >&2
  exit 1
}

info() {
  echo "[stage8] $*"
}

usage() {
  head -30 "$0" | grep "^#" | sed 's/^# //; s/^#//'
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
    --bench) BENCH="$(resolve_path "$2")"; shift 2 ;;
    --results-dir) RESULTS_BASE="$2"; shift 2 ;;
    --hint-mode) HINT_MODE="$2"; shift 2 ;;
    --trace-mode) TRACE_MODE="$2"; shift 2 ;;
    --skip-counters) SKIP_COUNTERS=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage ;;
    -*)
      if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH="$1"
      elif [[ -z "$BLOCK_DEV" ]]; then
        BLOCK_DEV="$1"
      else
        fail "unknown option: $1"
      fi
      shift ;;
    *)
      if [[ -z "$FILE_PATH" ]]; then
        FILE_PATH="$1"
      elif [[ -z "$BLOCK_DEV" ]]; then
        BLOCK_DEV="$1"
      else
        fail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

if [[ -z "$FILE_PATH" || -z "$BLOCK_DEV" ]]; then
  usage
fi

if [[ ! "$BENCH" = /* ]]; then
  BENCH="$(resolve_path "$BENCH")"
fi

RESULTS_DIR="$RESULTS_BASE/$TIMESTAMP"

if $DRY_RUN; then
  info "DRY RUN: commands will be printed but not executed"
fi

# Check tracepoint availability
tracepoints_available=false
if [[ -d /sys/kernel/tracing/events/kairo ]]; then
  tracepoints_available=true
  info "Kairo tracepoints detected at /sys/kernel/tracing/events/kairo"
elif [[ -d /sys/kernel/debug/tracing/events/kairo ]]; then
  tracepoints_available=true
  info "Kairo tracepoints detected at /sys/kernel/debug/tracing/events/kairo"
else
  info "Kairo tracepoints not detected (expected on unpatched kernels)"
fi

# Resolve trace mode
if [[ "$TRACE_MODE" == "auto" ]]; then
  if $tracepoints_available; then
    if command -v bpftrace &>/dev/null; then
      TRACE_MODE="bpftrace"
    else
      TRACE_MODE="ftrace"
    fi
  else
    TRACE_MODE="none"
  fi
fi
info "Trace mode: $TRACE_MODE"

# Create results directory
dry_cmd() {
  if $DRY_RUN; then
    echo "  $*"
  else
    # shellcheck disable=SC2294
    eval "$@"
  fi
}

if ! $DRY_RUN; then
  mkdir -p "$RESULTS_DIR/trace" "$RESULTS_DIR/counters-before" "$RESULTS_DIR/counters-after"
fi

if $DRY_RUN; then
  info "Would create results under $RESULTS_DIR"
else
  info "Created results directory $RESULTS_DIR"
fi

# Save run metadata
if $DRY_RUN; then
  cat <<EOF
stage=8
timestamp=$TIMESTAMP
file_path=$FILE_PATH
block_dev=$BLOCK_DEV
duration=$DURATION
hint_mode=$HINT_MODE
trace_mode=$TRACE_MODE
tracepoints_available=$tracepoints_available
bench=$BENCH
results_dir=$RESULTS_DIR
skip_counters=$SKIP_COUNTERS
dry_run=$DRY_RUN
EOF
else
cat > "$RESULTS_DIR/run_metadata.log" <<EOF
stage=8
timestamp=$TIMESTAMP
file_path=$FILE_PATH
block_dev=$BLOCK_DEV
duration=$DURATION
hint_mode=$HINT_MODE
trace_mode=$TRACE_MODE
tracepoints_available=$tracepoints_available
bench=$BENCH
results_dir=$RESULTS_DIR
skip_counters=$SKIP_COUNTERS
dry_run=$DRY_RUN
EOF
info "Run metadata saved to $RESULTS_DIR/run_metadata.log"
fi

# Save available trace events
if $tracepoints_available; then
  dry_cmd "cat /sys/kernel/tracing/events/kairo/*/format > \"$RESULTS_DIR/trace/available_events.log\" 2>/dev/null || \
           cat /sys/kernel/debug/tracing/events/kairo/*/format > \"$RESULTS_DIR/trace/available_events.log\" 2>/dev/null"
fi

# Collect pre-benchmark counters
counter_collect() {
  local outdir="$1"
  if $SKIP_COUNTERS; then
    info "Skipping counter collection"
    return
  fi
  if [[ -f "$REPO_ROOT/scripts/collect_kairo_counters.sh" ]]; then
    dry_cmd "bash \"$REPO_ROOT/scripts/collect_kairo_counters.sh\" \"$outdir/counters.txt\" 2>&1 || true"
  fi
  if [[ -b "/dev/$BLOCK_DEV" ]]; then
    for dev in "$BLOCK_DEV" "${BLOCK_DEV}p1" "${BLOCK_DEV}n1"; do
      if [[ -d "/sys/block/$dev/queue/scheduler" ]]; then
        dry_cmd "cat \"/sys/block/$dev/queue/scheduler\" > \"$outdir/scheduler_$dev.txt\" 2>/dev/null || true"
      fi
    done
  fi
}

info "Collecting pre-benchmark counters..."
counter_collect "$RESULTS_DIR/counters-before"

# Start ftrace if applicable
ftrace_pid=""
if [[ "$TRACE_MODE" == "ftrace" ]] && $tracepoints_available; then
  info "Starting ftrace capture..."
  dry_cmd "echo 0 > /sys/kernel/tracing/tracing_on 2>/dev/null || true"
  dry_cmd "echo > /sys/kernel/tracing/trace 2>/dev/null || true"
  dry_cmd "echo kairo > /sys/kernel/tracing/current_tracer 2>/dev/null || true"
  dry_cmd "echo 1 > /sys/kernel/tracing/events/kairo/enable 2>/dev/null || true"
  dry_cmd "echo 1 > /sys/kernel/tracing/tracing_on 2>/dev/null || true"

  if ! $DRY_RUN; then
    cat /sys/kernel/tracing/trace_pipe > "$RESULTS_DIR/trace/kairo_trace.log" &
    ftrace_pid=$!
  fi
fi

# Run benchmark
bench_args=(
  "--file" "$FILE_PATH"
  "--duration" "$DURATION"
  "--hint-mode" "$HINT_MODE"
  "--backend-mode" "generic"
)

if [[ -f "$BENCH" ]]; then
  info "Running benchmark: $BENCH ${bench_args[*]}"
  if $DRY_RUN; then
    echo "  $BENCH ${bench_args[*]}"
  else
    set +e
    "$BENCH" "${bench_args[@]}" > "$RESULTS_DIR/benchmark.log" 2>&1
    bench_exit=$?
    set -e
    info "Benchmark exit code: $bench_exit"
  fi
else
  info "Benchmark binary not found at $BENCH; skipping benchmark run"
  echo "benchmark_binary_not_found=true" >> "$RESULTS_DIR/run_metadata.log"
fi

# Stop ftrace
if [[ -n "$ftrace_pid" ]]; then
  info "Stopping ftrace..."
  dry_cmd "echo 0 > /sys/kernel/tracing/tracing_on 2>/dev/null || true"
  dry_cmd "echo 0 > /sys/kernel/tracing/events/kairo/enable 2>/dev/null || true"
  if ! $DRY_RUN; then
    kill "$ftrace_pid" 2>/dev/null || true
    wait "$ftrace_pid" 2>/dev/null || true
  fi
fi

# Run bpftrace scripts if applicable
if [[ "$TRACE_MODE" == "bpftrace" ]] && $tracepoints_available; then
  if command -v bpftrace &>/dev/null; then
    for script in kairo_latency.bt kairo_dispatch.bt kairo_backend.bt; do
      script_path="$REPO_ROOT/scripts/bpftrace/$script"
      if [[ -f "$script_path" ]]; then
        info "Running bpftrace script: $script"
        dry_cmd "bpftrace \"$script_path\" > \"$RESULTS_DIR/trace/${script%.bt}.log\" 2>&1 &"
        if ! $DRY_RUN; then
          sleep 2
        fi
      fi
    done
    if ! $DRY_RUN; then
      sleep "$DURATION"
      pkill -f "bpftrace.*kairo" 2>/dev/null || true
    fi
  else
    info "bpftrace not found; skipping bpftrace scripts"
  fi
fi

# Collect post-benchmark counters
info "Collecting post-benchmark counters..."
counter_collect "$RESULTS_DIR/counters-after"

# Generate summary
summary_file="$RESULTS_DIR/summary.log"
if $DRY_RUN; then
  info "Dry run complete; summary files were not written."
else
  {
    echo "stage8_trace_experiment"
    echo "timestamp=$TIMESTAMP"
    echo "file_path=$FILE_PATH"
    echo "block_dev=$BLOCK_DEV"
    echo "duration=$DURATION"
    echo "hint_mode=$HINT_MODE"
    echo "trace_mode=$TRACE_MODE"
    echo "tracepoints_available=$tracepoints_available"
    echo "results_dir=$RESULTS_DIR"

    if [[ -f "$RESULTS_DIR/benchmark.log" ]]; then
      grep -E "^(decode_|prefetch_|write_|evict_|backend_|ioprio_|rwf_)" \
        "$RESULTS_DIR/benchmark.log" || true
    fi
  } > "$summary_file"

  # Generate CSV summary
  csv_file="$RESULTS_DIR/summary.csv"
  {
    echo "event,value"
    echo "tracepoints_available,$tracepoints_available"
    if [[ -f "$RESULTS_DIR/benchmark.log" ]]; then
      grep -E "^(decode_|prefetch_|write_|evict_|backend_|ioprio_|rwf_)" \
        "$RESULTS_DIR/benchmark.log" | sed 's/^/=/' | tr '=' ',' || true
    fi
  } > "$csv_file"

  info "Results saved to $RESULTS_DIR"
  info "Summary: $summary_file"
  info "CSV: $csv_file"
fi

if [[ "$TRACE_MODE" == "none" ]]; then
  info "Tracepoints were not available. Run on a patched kernel for trace data."
fi
