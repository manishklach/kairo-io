#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <file-path> <block-device>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TARGET_FILE="$1"
BLOCK_DEVICE="$2"
BENCH_BIN="$REPO_ROOT/kairo_bench"
SCHEDULER_FILE="/sys/block/$BLOCK_DEVICE/queue/scheduler"
IOSCHED_DIR="/sys/block/$BLOCK_DEVICE/queue/iosched"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$REPO_ROOT/results/ab/$STAMP"
BASELINE_LOG="$OUT_DIR/baseline.log"
KAIRO_LOG="$OUT_DIR/kairo.log"

required_files=(
  "$IOSCHED_DIR/kairo_enable"
  "$IOSCHED_DIR/kairo_decode_dispatches"
  "$IOSCHED_DIR/kairo_normal_dispatches"
  "$IOSCHED_DIR/kairo_starvation_escapes"
)

metric_from_log() {
  local key="$1"
  local file="$2"
  awk -F= -v key="$key" '$1 == key { print $2 }' "$file" | tail -n1
}

counter_value() {
  local name="$1"
  if [[ -r "$IOSCHED_DIR/$name" ]]; then
    cat "$IOSCHED_DIR/$name"
  else
    echo ""
  fi
}

calc_pct_change() {
  local base="$1"
  local current="$2"
  awk -v base="$base" -v current="$current" 'BEGIN {
    if (base + 0 == 0) {
      print "nan";
    } else {
      printf "%.2f", ((base - current) / base) * 100.0;
    }
  }'
}

calc_pct_delta() {
  local base="$1"
  local current="$2"
  awk -v base="$base" -v current="$current" 'BEGIN {
    if (base + 0 == 0) {
      print "nan";
    } else {
      printf "%.2f", ((current - base) / base) * 100.0;
    }
  }'
}

run_bench_to_log() {
  local log_file="$1"
  "$BENCH_BIN" \
    --file "$TARGET_FILE" \
    --mode mixed \
    --size 8G \
    --block-size 1M \
    --decode-threads 4 \
    --prefetch-threads 1 \
    --write-threads 2 \
    --evict-threads 1 \
    --sessions 4 \
    --models 2 \
    --runtime 60 \
    --random-read | tee "$log_file"
}

if [[ ! -x "$BENCH_BIN" ]]; then
  echo "[kairo] building benchmark first"
  "$REPO_ROOT/scripts/build_bench.sh"
fi

if [[ ! -w "$SCHEDULER_FILE" ]]; then
  echo "[kairo] scheduler control is not writable: $SCHEDULER_FILE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

echo "[kairo] selecting mq-deadline on $BLOCK_DEVICE"
printf '%s\n' mq-deadline >"$SCHEDULER_FILE"
cat "$SCHEDULER_FILE" | tee "$OUT_DIR/scheduler.txt"

if ! grep -q '\[mq-deadline\]' "$SCHEDULER_FILE"; then
  echo "[kairo] mq-deadline is not active on $BLOCK_DEVICE" >&2
  exit 1
fi

for path in "${required_files[@]}"; do
  if [[ ! -r "$path" ]]; then
    echo "[kairo] missing Kairo sysfs file: $path" >&2
    exit 1
  fi
done

if [[ -w "$IOSCHED_DIR/kairo_enable" ]]; then
  echo "[kairo] running baseline with kairo_enable=0"
  printf '%s\n' 0 >"$IOSCHED_DIR/kairo_enable"
else
  echo "[kairo] kairo_enable sysfs knob not writable; baseline will run with current kernel state"
fi

baseline_decode_before="$(counter_value kairo_decode_dispatches)"
baseline_normal_before="$(counter_value kairo_normal_dispatches)"
baseline_starvation_before="$(counter_value kairo_starvation_escapes)"

run_bench_to_log "$BASELINE_LOG"

baseline_decode_after="$(counter_value kairo_decode_dispatches)"
baseline_normal_after="$(counter_value kairo_normal_dispatches)"
baseline_starvation_after="$(counter_value kairo_starvation_escapes)"

if [[ -w "$IOSCHED_DIR/kairo_enable" ]]; then
  echo "[kairo] running Kairo path with kairo_enable=1"
  printf '%s\n' 1 >"$IOSCHED_DIR/kairo_enable"
fi

kairo_decode_before="$(counter_value kairo_decode_dispatches)"
kairo_normal_before="$(counter_value kairo_normal_dispatches)"
kairo_starvation_before="$(counter_value kairo_starvation_escapes)"

run_bench_to_log "$KAIRO_LOG"

kairo_decode_after="$(counter_value kairo_decode_dispatches)"
kairo_normal_after="$(counter_value kairo_normal_dispatches)"
kairo_starvation_after="$(counter_value kairo_starvation_escapes)"

baseline_p99="$(metric_from_log decode_p99_us "$BASELINE_LOG")"
kairo_p99="$(metric_from_log decode_p99_us "$KAIRO_LOG")"
baseline_avg="$(metric_from_log decode_avg_us "$BASELINE_LOG")"
kairo_avg="$(metric_from_log decode_avg_us "$KAIRO_LOG")"
baseline_p50="$(metric_from_log decode_p50_us "$BASELINE_LOG")"
kairo_p50="$(metric_from_log decode_p50_us "$KAIRO_LOG")"
baseline_p95="$(metric_from_log decode_p95_us "$BASELINE_LOG")"
kairo_p95="$(metric_from_log decode_p95_us "$KAIRO_LOG")"
baseline_max="$(metric_from_log decode_max_us "$BASELINE_LOG")"
kairo_max="$(metric_from_log decode_max_us "$KAIRO_LOG")"
baseline_decode_mbps="$(metric_from_log decode_read_MBps "$BASELINE_LOG")"
kairo_decode_mbps="$(metric_from_log decode_read_MBps "$KAIRO_LOG")"
baseline_write_mbps="$(metric_from_log write_MBps "$BASELINE_LOG")"
kairo_write_mbps="$(metric_from_log write_MBps "$KAIRO_LOG")"

p99_improvement_pct="$(calc_pct_change "$baseline_p99" "$kairo_p99")"
write_delta_pct="$(calc_pct_delta "$baseline_write_mbps" "$kairo_write_mbps")"
kairo_decode_delta=$((kairo_decode_after - kairo_decode_before))

cat >"$OUT_DIR/summary.txt" <<EOF
baseline_decode_avg_us=$baseline_avg
kairo_decode_avg_us=$kairo_avg
baseline_decode_p50_us=$baseline_p50
kairo_decode_p50_us=$kairo_p50
baseline_decode_p95_us=$baseline_p95
kairo_decode_p95_us=$kairo_p95
baseline_decode_p99_us=$baseline_p99
kairo_decode_p99_us=$kairo_p99
baseline_decode_max_us=$baseline_max
kairo_decode_max_us=$kairo_max
baseline_decode_read_MBps=$baseline_decode_mbps
kairo_decode_read_MBps=$kairo_decode_mbps
p99_improvement_pct=$p99_improvement_pct
baseline_write_MBps=$baseline_write_mbps
kairo_write_MBps=$kairo_write_mbps
write_delta_pct=$write_delta_pct
kairo_decode_dispatches_delta=$kairo_decode_delta
baseline_kairo_decode_dispatches_delta=$((baseline_decode_after - baseline_decode_before))
baseline_kairo_normal_dispatches_delta=$((baseline_normal_after - baseline_normal_before))
baseline_kairo_starvation_escapes_delta=$((baseline_starvation_after - baseline_starvation_before))
kairo_normal_dispatches_delta=$((kairo_normal_after - kairo_normal_before))
kairo_starvation_escapes_delta=$((kairo_starvation_after - kairo_starvation_before))
EOF

echo "baseline_decode_p99_us=$baseline_p99"
echo "kairo_decode_p99_us=$kairo_p99"
echo "baseline_decode_p95_us=$baseline_p95"
echo "kairo_decode_p95_us=$kairo_p95"
echo "baseline_decode_avg_us=$baseline_avg"
echo "kairo_decode_avg_us=$kairo_avg"
echo "p99_improvement_pct=$p99_improvement_pct"
echo "baseline_write_MBps=$baseline_write_mbps"
echo "kairo_write_MBps=$kairo_write_mbps"
echo "write_delta_pct=$write_delta_pct"
echo "kairo_decode_dispatches_delta=$kairo_decode_delta"
echo "[kairo] logs saved in $OUT_DIR"
