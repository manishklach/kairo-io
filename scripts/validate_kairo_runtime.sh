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

required_files=(
  "$IOSCHED_DIR/kairo_enable"
  "$IOSCHED_DIR/kairo_decode_budget"
  "$IOSCHED_DIR/kairo_decode_dispatches"
  "$IOSCHED_DIR/kairo_normal_dispatches"
  "$IOSCHED_DIR/kairo_starvation_escapes"
)

read_counter() {
  cat "$1"
}

if [[ ! -x "$BENCH_BIN" ]]; then
  echo "[kairo] building benchmark first"
  "$REPO_ROOT/scripts/build_bench.sh"
fi

if [[ ! -e "$TARGET_FILE" ]]; then
  echo "[kairo] target file does not exist yet, it will be created by kairo_bench: $TARGET_FILE"
fi

if [[ ! -w "$SCHEDULER_FILE" ]]; then
  echo "[kairo] scheduler control is not writable: $SCHEDULER_FILE" >&2
  exit 1
fi

echo "[kairo] selecting mq-deadline on $BLOCK_DEVICE"
printf '%s\n' mq-deadline >"$SCHEDULER_FILE"

echo "[kairo] scheduler state"
cat "$SCHEDULER_FILE"

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

before_decode="$(read_counter "$IOSCHED_DIR/kairo_decode_dispatches")"
before_normal="$(read_counter "$IOSCHED_DIR/kairo_normal_dispatches")"
before_starvation="$(read_counter "$IOSCHED_DIR/kairo_starvation_escapes")"

echo "[kairo] counter snapshot before benchmark"
echo "kairo_decode_dispatches_before=$before_decode"
echo "kairo_normal_dispatches_before=$before_normal"
echo "kairo_starvation_escapes_before=$before_starvation"

"$BENCH_BIN" \
  --file "$TARGET_FILE" \
  --size 8G \
  --block-size 1M \
  --decode-threads 4 \
  --prefetch-threads 1 \
  --write-threads 2 \
  --runtime 60 \
  --random-read

after_decode="$(read_counter "$IOSCHED_DIR/kairo_decode_dispatches")"
after_normal="$(read_counter "$IOSCHED_DIR/kairo_normal_dispatches")"
after_starvation="$(read_counter "$IOSCHED_DIR/kairo_starvation_escapes")"

decode_delta=$((after_decode - before_decode))
normal_delta=$((after_normal - before_normal))
starvation_delta=$((after_starvation - before_starvation))

echo "[kairo] counter snapshot after benchmark"
echo "kairo_decode_dispatches_after=$after_decode"
echo "kairo_normal_dispatches_after=$after_normal"
echo "kairo_starvation_escapes_after=$after_starvation"
echo "kairo_decode_dispatches_delta=$decode_delta"
echo "kairo_normal_dispatches_delta=$normal_delta"
echo "kairo_starvation_escapes_delta=$starvation_delta"

if [[ $decode_delta -eq 0 ]]; then
  echo "Kairo decode path was not hit."
fi
