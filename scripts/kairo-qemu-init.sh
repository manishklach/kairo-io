#!/bin/sh
# Minimal initramfs init for Kairo QEMU boot validation.
#
# Mounts sysfs/procfs, loads kairo_validation_mod.ko, checks Kairo sysfs
# counters under /sys/kernel/kairo/counters/, optionally runs kairo_bench,
# reports results, and powers off.

set -e

echo "[kairo-qemu] Booting Kairo-validated kernel"
uname -a

# Mount essential filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t tmpfs none /tmp
mount -t devtmpfs none /dev

echo "[kairo-qemu] sysfs and procfs mounted"

# Load the Kairo validation module
echo "[kairo-qemu] Loading kairo_validation_mod.ko..."
if [ -f /kairo_validation_mod.ko ]; then
    insmod /kairo_validation_mod.ko 2>&1 && echo "[kairo-qemu]   module loaded" || echo "[kairo-qemu]   module load FAILED"
else
    echo "[kairo-qemu]   module not found in initramfs"
fi

# Check kairo sysfs presence
KAIRO_SYSFS="/sys/kernel/kairo/counters"
PASS=0
FAIL=0

check_counter() {
  _name="$1"
  _file="$KAIRO_SYSFS/$_name"
  if [ -r "$_file" ]; then
    _val=$(cat "$_file" 2>/dev/null || echo "unreadable")
    echo "[kairo-qemu]   COUNTER $_name = $_val"
    PASS=$((PASS + 1))
  else
    echo "[kairo-qemu]   MISSING $_name"
    FAIL=$((FAIL + 1))
  fi
}

echo "[kairo-qemu] Checking Kairo sysfs counters at $KAIRO_SYSFS..."

# Stage 1-9: dispatch counters
check_counter "decode_dispatches"
check_counter "prefetch_dispatches"
check_counter "prefetch_deadline_hits"
check_counter "prefetch_budget_skips"
check_counter "prefill_dispatches"
check_counter "evict_dispatches"
check_counter "normal_dispatches"
check_counter "starvation_escapes"
check_counter "hinted_requests"
check_counter "unhinted_requests"

# Stage 25: fairness counters
check_counter "fairness_decode_budget_used"
check_counter "fairness_prefetch_budget_used"
check_counter "fairness_epoch_cycles"

# Stage 26: blkcg counters
check_counter "blkcg_iops_read"
check_counter "blkcg_iops_write"
check_counter "blkcg_latency_avg_us"
check_counter "blkcg_token_deficit"

# Stage 17: KV region
check_counter "kv_region_hints"
check_counter "kv_region_hits"
check_counter "kv_region_misses"

# Stage 18: eviction
check_counter "eviction_total"
check_counter "eviction_recomputed"
check_counter "eviction_kv_cache"
check_counter "eviction_model_local"
check_counter "eviction_decode_hot"
check_counter "eviction_session_private"
check_counter "eviction_persistent"
check_counter "eviction_other"

# Stage 19: heatmap
check_counter "heat_scan_regions"
check_counter "heat_active_regions"
check_counter "heat_cold_regions"
check_counter "heat_frozen_regions"
check_counter "heat_reheat_count"
check_counter "heat_age_decay_count"
check_counter "heat_promotions"
check_counter "heat_demotions"

# Stage 20: admission
check_counter "admit_accepted"
check_counter "admit_rejected_recompute"
check_counter "admit_rejected_lifetime"
check_counter "admit_rejected_flash_pressure"
check_counter "admit_rejected_reuse"
check_counter "admit_rejected_policy"
check_counter "admit_promoted"
check_counter "admit_demoted"

# Check version
if [ -r /sys/kernel/kairo/version ]; then
    ver=$(cat /sys/kernel/kairo/version)
    echo "[kairo-qemu]   kairo version = $ver"
    PASS=$((PASS + 1))
else
    echo "[kairo-qemu]   MISSING version"
    FAIL=$((FAIL + 1))
fi

echo "[kairo-qemu] === COUNTER CHECK RESULT ==="
echo "[kairo-qemu]   found=$PASS missing=$FAIL"

# Try running kairo_bench if available
if [ -x /kairo_bench ]; then
  echo "[kairo-qemu] kairo_bench found, running smoke test..."
  dd if=/dev/zero of=/tmp/kairo_test.bin bs=1M count=64 2>/dev/null
  set +e
  /kairo_bench --file /tmp/kairo_test.bin --runtime 5 \
    --decode-threads 1 --prefetch-threads 1 --write-threads 1 \
    --kv-region-id 0 --kv-region-type decode --kv-region-count 10 \
    --eviction-policy recompute-aware \
    --heatmap-mode region \
    --admission-mode policy \
    > /tmp/bench_result.log 2>&1
  BENCH_EXIT=$?
  set -e
  echo "[kairo-qemu] kairo_bench exit code: $BENCH_EXIT"
  cat /tmp/bench_result.log
else
  echo "[kairo-qemu] kairo_bench not included in initramfs"
fi

echo "[kairo-qemu] === KAIRO QEMU VALIDATION COMPLETE ==="
echo "[kairo-qemu] PASS:$PASS FAIL:$FAIL"
sleep 1
poweroff -f
