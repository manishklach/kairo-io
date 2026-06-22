#!/usr/bin/env bash
#
# run_stage6_placement_experiment.sh
#
# Stage 6: model/session/lifetime placement metadata experiment.
#
# Runs the Kairo benchmark with various cache-pool and placement-group
# configurations to exercise the Stage 6 placement/lifetime metadata path.
#
# Usage:
#   ./run_stage6_placement_experiment.sh [--file <path>] [--duration <sec>]
#
# Options:
#   --file <path>       Target file path (default: /tmp/kairo_stage6.bin)
#   --duration <sec>    Per-run duration (default: 30)
#   --help              Show this help

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BENCH="${SCRIPT_DIR}/../bench/kairo_bench"
FILE="${FILE:-/tmp/kairo_stage6.bin}"
DURATION="${DURATION:-30}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --help) grep '^#' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done

run_bench() {
  local label="$1"
  shift
  echo "=== Run: ${label} ==="
  "${BENCH}" \
    --file "${FILE}" \
    --runtime "${DURATION}" \
    --mode mixed \
    --decode-threads 2 \
    --prefetch-threads 1 \
    --write-threads 1 \
    --evict-threads 0 \
    --hint-mode ioprio \
    "$@"
  echo ""
}

echo "========================================"
echo " Stage 6: Placement/Lifetime Experiment"
echo "========================================"
echo "Benchmark: ${BENCH}"
echo "Target:    ${FILE}"
echo "Duration:  ${DURATION}s"
echo ""

# Baseline (no placement metadata)
run_bench "baseline (no placement metadata)"

# Fixed model-id only
run_bench "fixed model-id=1" \
  --model-id 1

# Fixed session-id only
run_bench "fixed session-id=42" \
  --session-id 42

# Fixed cache-pool-id and placement-group
run_bench "fixed cache-pool-id=3 placement-group=5" \
  --cache-pool-id 3 \
  --placement-group 5

# Lifetime classes
run_bench "lifetime=short" \
  --lifetime short

run_bench "lifetime=session" \
  --lifetime session

run_bench "lifetime=model" \
  --lifetime model

run_bench "lifetime=persistent" \
  --lifetime persistent

# Recompute-ok flag
run_bench "recompute-ok" \
  --recompute-ok

# Multiple cache pools and placement groups (distributed)
run_bench "cache-pools=4 placement-groups=2" \
  --cache-pools 4 \
  --placement-groups 2

# Combine many options
run_bench "combined: short+recompute+model-id+session-id" \
  --model-id 1 \
  --session-id 5 \
  --cache-pool-id 2 \
  --placement-group 3 \
  --lifetime short \
  --recompute-ok

# Multisession mode with placement metadata
run_bench "multisession + cache-pools=4" \
  --mode multisession \
  --sessions 4 \
  --models 2 \
  --cache-pools 4 \
  --placement-groups 2 \
  --lifetime session

echo "========================================"
echo " Stage 6 experiment complete."
echo "========================================"
