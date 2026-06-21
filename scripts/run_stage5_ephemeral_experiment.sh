#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BENCH_PATH="$REPO_ROOT/kairo_bench"
COLLECT="$SCRIPT_DIR/collect_kairo_counters.sh"
RESULTS_DIR="$REPO_ROOT/results/stage5/$(date +%Y%m%d-%H%M%S)"
IOSCHED_DIR=""

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <file-path> <block-device>" >&2
  exit 1
fi

FILE="$1"
DEV="$2"
IOSCHED_DIR="/sys/block/$DEV/queue/iosched"

if [[ ! -x "$BENCH_PATH" ]]; then
  echo "error: expected benchmark at $BENCH_PATH" >&2
  echo "build it first: gcc -O2 -Wall -pthread -Iinclude -o kairo_bench bench/kairo_bench.c" >&2
  exit 1
fi

mkdir -p "$RESULTS_DIR"

counter_delta() {
  local before_dir="$1"
  local after_dir="$2"
  local counter="$3"
  local before_val=0
  local after_val=0

  [[ -f "$before_dir/$counter.txt" ]] && before_val=$(cat "$before_dir/$counter.txt" 2>/dev/null || echo 0)
  [[ -f "$after_dir/$counter.txt" ]] && after_val=$(cat "$after_dir/$counter.txt" 2>/dev/null || echo 0)
  echo $(( after_val - before_val ))
}

run_case() {
  local case_name="$1"
  local semantic_mode="$2"
  local case_dir="$RESULTS_DIR/$case_name"
  mkdir -p "$case_dir"

  if [[ -w "$IOSCHED_DIR/kairo_enable" ]]; then
    echo "1" | sudo tee "$IOSCHED_DIR/kairo_enable" >/dev/null
  fi

  "$COLLECT" "$DEV" "$case_dir/before" 2>/dev/null || true

  "$BENCH_PATH" \
    --file "$FILE" \
    --mode eviction-pressure \
    --hint-mode both \
    --semantic-mode "$semantic_mode" \
    --runtime 30 \
    --evict-threads 2 \
    --decode-threads 4 \
    --prefetch-threads 2 \
    --write-threads 2 \
    --block-size 1M \
    --size 4G \
    2>&1 | tee "$case_dir/bench.log"

  "$COLLECT" "$DEV" "$case_dir/after" 2>/dev/null || true

  local decode_p99 write_mbps evictions
  local rwf_ephemeral_attempts rwf_ephemeral_fail rwf_recompute_attempts rwf_recompute_fail
  local ephemeral_delta recomputable_delta cleanup_delta

  decode_p99=$(grep '^decode_p99_us=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  write_mbps=$(grep '^write_MBps=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  evictions=$(grep '^evict_total_ops=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  rwf_ephemeral_attempts=$(grep '^rwf_ephemeral_attempts=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  rwf_ephemeral_fail=$(grep '^rwf_ephemeral_fail=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  rwf_recompute_attempts=$(grep '^rwf_recompute_attempts=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  rwf_recompute_fail=$(grep '^rwf_recompute_fail=' "$case_dir/bench.log" | tail -n1 | cut -d= -f2-)
  ephemeral_delta=$(counter_delta "$case_dir/before" "$case_dir/after" "kairo_ephemeral_requests")
  recomputable_delta=$(counter_delta "$case_dir/before" "$case_dir/after" "kairo_recomputable_requests")
  cleanup_delta=$(counter_delta "$case_dir/before" "$case_dir/after" "kairo_evict_cleanup_requests")

  {
    echo "case=$case_name"
    echo "semantic_mode=$semantic_mode"
    echo "decode_p99_us=${decode_p99:-0}"
    echo "write_MBps=${write_mbps:-0}"
    echo "evictions=${evictions:-0}"
    echo "rwf_ephemeral_attempts=${rwf_ephemeral_attempts:-0}"
    echo "rwf_ephemeral_fail=${rwf_ephemeral_fail:-0}"
    echo "rwf_recompute_attempts=${rwf_recompute_attempts:-0}"
    echo "rwf_recompute_fail=${rwf_recompute_fail:-0}"
    echo "kairo_ephemeral_requests_delta=$ephemeral_delta"
    echo "kairo_recomputable_requests_delta=$recomputable_delta"
    echo "kairo_evict_cleanup_delta=$cleanup_delta"
  } | tee "$case_dir/summary.log"
}

run_case "01-normal" "normal"
run_case "02-ephemeral" "ephemeral"
run_case "03-recomputable" "recomputable"
run_case "04-ephemeral-recomputable" "ephemeral-recomputable"

echo "results_dir=$RESULTS_DIR"
