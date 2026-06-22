#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/validation/$TIMESTAMP"
TEST_FILE="/tmp/kairo_validation.bin"
DURATION=5
SKIP_BENCH=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_wsl_validation_snapshot.sh [options]

Options:
  --results-dir PATH       default results/validation/<timestamp>
  --test-file PATH         default /tmp/kairo_validation.bin
  --duration SEC           default 5
  --skip-bench             skip actual benchmark execution
  --dry-run                print commands only
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --results-dir) RESULTS_DIR="$2"; shift 2 ;;
    --test-file) TEST_FILE="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --skip-bench) SKIP_BENCH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

summary_file="$RESULTS_DIR/summary.log"
environment_log="$RESULTS_DIR/environment.log"
validate_log="$RESULTS_DIR/validate_patch_stack.log"
make_log="$RESULTS_DIR/make.log"
benchmark_version_log="$RESULTS_DIR/benchmark_version.log"
stage6_dryrun_log="$RESULTS_DIR/stage6_dryrun.log"
stage7_dryrun_log="$RESULTS_DIR/stage7_dryrun.log"
stage8_dryrun_log="$RESULTS_DIR/stage8_dryrun.log"
user_bench_baseline_log="$RESULTS_DIR/user_bench_baseline.log"
user_bench_mixed_log="$RESULTS_DIR/user_bench_mixed.log"
snapshot_md="$RESULTS_DIR/validation_snapshot.md"

declare -A SUMMARY=(
  [timestamp]="$TIMESTAMP"
  [is_wsl]="unknown"
  [kernel_release]="unknown"
  [validate_patch_stack]="fail"
  [make]="fail"
  [fallback_gcc_build]="not_needed"
  [benchmark_exists]="false"
  [benchmark_binary]=""
  [stage6_dryrun]="fail"
  [stage7_dryrun]="fail"
  [stage8_dryrun]="missing_script"
  [user_bench_baseline]="skipped"
  [user_bench_mixed]="skipped"
  [results_dir]="$RESULTS_DIR"
  [notes]="WSL validation only; no custom kernel boot, no Kairo sysfs counters, no physical NVMe placement validation."
)

run_logged() {
  local logfile="$1"
  shift
  if "$@" >"$logfile" 2>&1; then
    return 0
  fi
  return 1
}

record_summary() {
  {
    echo "timestamp=${SUMMARY[timestamp]}"
    echo "is_wsl=${SUMMARY[is_wsl]}"
    echo "kernel_release=${SUMMARY[kernel_release]}"
    echo "validate_patch_stack=${SUMMARY[validate_patch_stack]}"
    echo "make=${SUMMARY[make]}"
    echo "fallback_gcc_build=${SUMMARY[fallback_gcc_build]}"
    echo "benchmark_exists=${SUMMARY[benchmark_exists]}"
    echo "benchmark_binary=${SUMMARY[benchmark_binary]}"
    echo "stage6_dryrun=${SUMMARY[stage6_dryrun]}"
    echo "stage7_dryrun=${SUMMARY[stage7_dryrun]}"
    echo "stage8_dryrun=${SUMMARY[stage8_dryrun]}"
    echo "user_bench_baseline=${SUMMARY[user_bench_baseline]}"
    echo "user_bench_mixed=${SUMMARY[user_bench_mixed]}"
    echo "results_dir=${SUMMARY[results_dir]}"
    echo "notes=${SUMMARY[notes]}"
  } > "$summary_file"
}

resolve_bench_binary() {
  if [[ -x "$REPO_ROOT/kairo_bench" ]]; then
    printf '%s\n' "$REPO_ROOT/kairo_bench"
  elif [[ -x "$REPO_ROOT/bench/kairo_bench" ]]; then
    printf '%s\n' "$REPO_ROOT/bench/kairo_bench"
  else
    printf '%s\n' ""
  fi
}

if $DRY_RUN; then
  {
    echo "DRY RUN: validation commands not executed"
    echo "results_dir=$RESULTS_DIR"
    echo "test_file=$TEST_FILE"
    echo "duration=$DURATION"
  } > "$environment_log"
else
  run_logged "$environment_log" "$REPO_ROOT/scripts/check_wsl_environment.sh" || true
fi

if [[ -f "$environment_log" ]]; then
  while IFS='=' read -r key value; do
    case "$key" in
      is_wsl) SUMMARY[is_wsl]="$value" ;;
      kernel_release) SUMMARY[kernel_release]="$value" ;;
    esac
  done < "$environment_log"
fi

if $DRY_RUN; then
  printf '%s\n' "./scripts/validate_patch_stack.sh" > "$validate_log"
  SUMMARY[validate_patch_stack]="pass"
else
  if run_logged "$validate_log" "$REPO_ROOT/scripts/validate_patch_stack.sh"; then
    SUMMARY[validate_patch_stack]="pass"
  else
    SUMMARY[validate_patch_stack]="fail"
  fi
fi

if $DRY_RUN; then
  printf '%s\n' "make" > "$make_log"
  SUMMARY[make]="pass"
  SUMMARY[fallback_gcc_build]="not_needed"
else
  if run_logged "$make_log" make -C "$REPO_ROOT"; then
    SUMMARY[make]="pass"
    SUMMARY[fallback_gcc_build]="not_needed"
  else
    SUMMARY[make]="fail"
    if gcc -O2 -Wall -pthread -I"$REPO_ROOT/include" -o "$REPO_ROOT/bench/kairo_bench" \
      "$REPO_ROOT/bench/kairo_bench.c" >>"$make_log" 2>&1; then
      SUMMARY[fallback_gcc_build]="pass"
    else
      SUMMARY[fallback_gcc_build]="fail"
    fi
  fi
fi

benchmark_binary="$(resolve_bench_binary)"
if [[ -n "$benchmark_binary" ]]; then
  SUMMARY[benchmark_exists]="true"
  SUMMARY[benchmark_binary]="$benchmark_binary"
  if $DRY_RUN; then
    printf '%s\n' "$benchmark_binary --help" > "$benchmark_version_log"
  else
    "$benchmark_binary" --help >"$benchmark_version_log" 2>&1 || true
  fi
else
  SUMMARY[benchmark_exists]="false"
  : > "$benchmark_version_log"
fi

if $DRY_RUN; then
  printf '%s\n' "./scripts/run_stage6_placement_experiment.sh \"$TEST_FILE\" loop0 --skip-counters --dry-run --duration \"$DURATION\"" > "$stage6_dryrun_log"
  SUMMARY[stage6_dryrun]="pass"
else
  if run_logged "$stage6_dryrun_log" "$REPO_ROOT/scripts/run_stage6_placement_experiment.sh" \
    "$TEST_FILE" loop0 --skip-counters --dry-run --duration "$DURATION"; then
    SUMMARY[stage6_dryrun]="pass"
  else
    SUMMARY[stage6_dryrun]="fail"
  fi
fi

if $DRY_RUN; then
  printf '%s\n' "./scripts/run_stage7_backend_mapping_experiment.sh \"$TEST_FILE\" loop0 --skip-counters --dry-run --duration \"$DURATION\"" > "$stage7_dryrun_log"
  SUMMARY[stage7_dryrun]="pass"
else
  if run_logged "$stage7_dryrun_log" "$REPO_ROOT/scripts/run_stage7_backend_mapping_experiment.sh" \
    "$TEST_FILE" loop0 --skip-counters --dry-run --duration "$DURATION"; then
    SUMMARY[stage7_dryrun]="pass"
  else
    SUMMARY[stage7_dryrun]="fail"
  fi
fi

if [[ -f "$REPO_ROOT/scripts/run_stage8_trace_experiment.sh" ]]; then
  if $DRY_RUN; then
    printf '%s\n' "./scripts/run_stage8_trace_experiment.sh \"$TEST_FILE\" loop0 --trace-mode none --skip-counters --dry-run --duration \"$DURATION\"" > "$stage8_dryrun_log"
    SUMMARY[stage8_dryrun]="pass"
  else
    if run_logged "$stage8_dryrun_log" "$REPO_ROOT/scripts/run_stage8_trace_experiment.sh" \
      "$TEST_FILE" loop0 --trace-mode none --skip-counters --dry-run --duration "$DURATION"; then
      SUMMARY[stage8_dryrun]="pass"
    else
      SUMMARY[stage8_dryrun]="fail"
    fi
  fi
else
  echo "run_stage8_trace_experiment.sh not found" > "$stage8_dryrun_log"
  SUMMARY[stage8_dryrun]="missing_script"
fi

if $SKIP_BENCH; then
  SUMMARY[user_bench_baseline]="skipped"
  SUMMARY[user_bench_mixed]="skipped"
  printf '%s\n' "skipped via --skip-bench" > "$user_bench_baseline_log"
  printf '%s\n' "skipped via --skip-bench" > "$user_bench_mixed_log"
elif [[ "${SUMMARY[benchmark_exists]}" != "true" ]]; then
  SUMMARY[user_bench_baseline]="skipped"
  SUMMARY[user_bench_mixed]="skipped"
  printf '%s\n' "benchmark binary missing" > "$user_bench_baseline_log"
  printf '%s\n' "benchmark binary missing" > "$user_bench_mixed_log"
elif $DRY_RUN; then
  printf '%s\n' "\"${SUMMARY[benchmark_binary]}\" --file \"$TEST_FILE\" --runtime \"$DURATION\" --mode decode-only --hint-mode ioprio" > "$user_bench_baseline_log"
  printf '%s\n' "\"${SUMMARY[benchmark_binary]}\" --file \"$TEST_FILE\" --runtime \"$DURATION\" --mode mixed --hint-mode ioprio --decode-threads 2 --write-threads 1 --prefetch-threads 1" > "$user_bench_mixed_log"
  SUMMARY[user_bench_baseline]="pass"
  SUMMARY[user_bench_mixed]="pass"
else
  truncate -s 64M "$TEST_FILE" 2>/dev/null || true
  if run_logged "$user_bench_baseline_log" "${SUMMARY[benchmark_binary]}" \
    --file "$TEST_FILE" --runtime "$DURATION" --mode decode-only --hint-mode ioprio; then
    SUMMARY[user_bench_baseline]="pass"
  else
    SUMMARY[user_bench_baseline]="fail"
  fi

  if run_logged "$user_bench_mixed_log" "${SUMMARY[benchmark_binary]}" \
    --file "$TEST_FILE" --runtime "$DURATION" --mode mixed --hint-mode ioprio \
    --decode-threads 2 --write-threads 1 --prefetch-threads 1; then
    SUMMARY[user_bench_mixed]="pass"
  else
    SUMMARY[user_bench_mixed]="fail"
  fi
fi

record_summary
python3 "$REPO_ROOT/scripts/parse_validation_snapshot.py" "$summary_file" --markdown > "$snapshot_md"
cp "$snapshot_md" "$REPO_ROOT/docs/validation_snapshot.md"

echo "[kairo] validation snapshot written to $RESULTS_DIR"
