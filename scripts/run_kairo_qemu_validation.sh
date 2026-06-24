#!/usr/bin/env bash
# Kairo QEMU boot validation orchestrator.
#
# Builds a Kairo-patched Linux kernel, creates an initramfs with the
# kairo-qemu-init script and kairo_bench, boots under QEMU, and
# collects results.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BUILD_SCRIPT="$REPO_ROOT/kernel/integration/linux-6.8/build_kairo_qemu_kernel.sh"
INIT_SCRIPT="$REPO_ROOT/scripts/kairo-qemu-init.sh"
BENCH_BINARY="$REPO_ROOT/kairo_bench"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="$REPO_ROOT/results/qemu-validation/$TIMESTAMP"
KERNEL_IMAGE=""
LINUX_DIR="${LINUX_DIR:-$HOME/linux-6.8}"
KERNEL_CMDLINE="console=ttyS0,115200 panic=1 quiet"
MEM_MB="${MEM_MB:-1024}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_kairo_qemu_validation.sh [options]

Builds a Kairo-patched kernel, boots it under QEMU, and validates
sysfs counters + benchmark smoke test.

Options:
  --linux-dir DIR       Path to Linux 6.8 source (default: ~/linux-6.8)
  --kernel PATH         Pre-built kernel bzImage (skip build)
  --mem MB              QEMU memory in MB (default: 1024)
  --jobs N              Parallel make jobs (default: nproc)
  --dry-run             Print commands without running
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --linux-dir) LINUX_DIR="$2"; shift 2 ;;
    --kernel) KERNEL_IMAGE="$2"; shift 2 ;;
    --mem) MEM_MB="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage; exit 0 ;;
    *) echo "unknown: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "$RESULTS_DIR"

if [[ -z "$KERNEL_IMAGE" ]]; then
  echo "[kairo-qemu] === Building Kairo-patched kernel ==="
  if $DRY_RUN; then
    echo "  $BUILD_SCRIPT --linux-dir $LINUX_DIR --jobs $JOBS"
    KERNEL_IMAGE="$LINUX_DIR/arch/x86_64/boot/bzImage"
  else
    bash "$BUILD_SCRIPT" --linux-dir "$LINUX_DIR" --jobs "$JOBS" 2>&1 | \
      tee "$RESULTS_DIR/build_kernel.log"
    KERNEL_IMAGE="$LINUX_DIR/arch/x86_64/boot/bzImage"
    if [[ ! -f "$KERNEL_IMAGE" ]]; then
      echo "[kairo-qemu] Kernel build failed: $KERNEL_IMAGE not found"
      exit 1
    fi
  fi
else
  echo "[kairo-qemu] Using pre-built kernel: $KERNEL_IMAGE"
fi

echo "[kairo-qemu] === Creating initramfs ==="
INITRAMFS_DIR=$(mktemp -d)
trap 'rm -rf "$INITRAMFS_DIR"' EXIT

# Create minimal rootfs layout
mkdir -p "$INITRAMFS_DIR"/{dev,proc,sys,tmp,etc}

# Use the static init binary (supports all Kairo validation tasks)
STATIC_INIT="$REPO_ROOT/scripts/kairo_qemu_init_static"
if [[ -f "$STATIC_INIT" ]]; then
  cp "$STATIC_INIT" "$INITRAMFS_DIR/init"
  chmod +x "$INITRAMFS_DIR/init"
  echo "[kairo-qemu]   using static init binary: $STATIC_INIT"
else
  # Fallback to shell script init
  cp "$INIT_SCRIPT" "$INITRAMFS_DIR/init"
  chmod +x "$INITRAMFS_DIR/init"
  echo "[kairo-qemu]   using shell init script (may need busybox)"
  # Create device nodes
  mknod "$INITRAMFS_DIR/dev/console" c 5 1 2>/dev/null || true
  mknod "$INITRAMFS_DIR/dev/null"    c 1 3 2>/dev/null || true
  mknod "$INITRAMFS_DIR/dev/ttyS0"  c 4 64 2>/dev/null || true
fi

# Copy kairo_bench if available
if [[ -f "$BENCH_BINARY" ]]; then
  cp "$BENCH_BINARY" "$INITRAMFS_DIR/kairo_bench"
  echo "[kairo-qemu]   included kairo_bench"
  # Include shared libraries for the dynamically-linked binary
  mkdir -p "$INITRAMFS_DIR/lib64" "$INITRAMFS_DIR/lib/x86_64-linux-gnu"
  for lib in /lib64/ld-linux-x86-64.so.2 /lib/x86_64-linux-gnu/libc.so.6; do
    if [[ -f "$lib" ]]; then
      cp "$lib" "$INITRAMFS_DIR$lib" 2>/dev/null || true
    fi
  done
  echo "[kairo-qemu]   included shared libraries"
fi

# Copy kairo_validation_mod.ko if available
KAIRO_MODULE="$REPO_ROOT/kernel/kairo_validation_mod.ko"
if [[ -f "$KAIRO_MODULE" ]]; then
  cp "$KAIRO_MODULE" "$INITRAMFS_DIR/kairo_validation_mod.ko"
  echo "[kairo-qemu]   included kairo_validation_mod.ko"
else
  echo "[kairo-qemu]   WARNING: kairo_validation_mod.ko not found at $KAIRO_MODULE"
fi

# Build initramfs cpio archive
(
  cd "$INITRAMFS_DIR"
  find . | cpio -o -H newc -R root:root 2>/dev/null | gzip -9 > "$RESULTS_DIR/initramfs.cpio.gz"
)
echo "[kairo-qemu] initramfs: $RESULTS_DIR/initramfs.cpio.gz"

# Use TCG (software emulation) since KVM needs root
echo "[kairo-qemu]   acceleration: tcg cpu: qemu64 (KVM unavailable without root)"

# Generate QEMU launch command
QEMU_CMD=(
  qemu-system-x86_64
  -machine type=q35,accel=tcg
  -cpu qemu64
  -m "$MEM_MB"
  -kernel "$KERNEL_IMAGE"
  -initrd "$RESULTS_DIR/initramfs.cpio.gz"
  -append "$KERNEL_CMDLINE"
  -serial file:"$RESULTS_DIR/serial.log"
  -nographic
  -display none
  -no-reboot
)

echo "[kairo-qemu] === Launching QEMU ==="
echo "[kairo-qemu]   kernel: $KERNEL_IMAGE"
echo "[kairo-qemu]   memory: ${MEM_MB}MB"
echo "[kairo-qemu]   output: $RESULTS_DIR/serial.log"
if $DRY_RUN; then
  echo "[kairo-qemu] DRY RUN - would execute:"
  echo "  ${QEMU_CMD[*]}"
  echo "[kairo-qemu] PASS (dry-run)"
  exit 0
fi

# Run QEMU with timeout
TIMEOUT_SEC=120
echo "[kairo-qemu] Running QEMU (timeout: ${TIMEOUT_SEC}s)..."
set +e
timeout "$TIMEOUT_SEC" bash -c 'exec "$@"' bash "${QEMU_CMD[@]}" 2>&1 | \
  tee "$RESULTS_DIR/qemu_stdout.log"
QEMU_EXIT=$?
set -e

echo "[kairo-qemu] QEMU exit code: $QEMU_EXIT"

# Parse results from serial log
SERIAL_LOG="$RESULTS_DIR/serial.log"
if [[ -f "$SERIAL_LOG" ]]; then
  echo "[kairo-qemu] === Parsing results ==="
  grep -E '\[kairo-qemu\]' "$SERIAL_LOG" > "$RESULTS_DIR/validation.log" || true
  grep -E '^RESULT|counters_found|counters_missing' "$SERIAL_LOG" > "$RESULTS_DIR/counters.log" || true
  cat "$RESULTS_DIR/counters.log" 2>/dev/null || echo "no counters found"

  # Check for key markers
  if grep -q 'VALIDATION COMPLETE' "$SERIAL_LOG"; then
    echo "[kairo-qemu] BOOT VALIDATION: PASS"
  else
    echo "[kairo-qemu] BOOT VALIDATION: FAIL (did not complete)"
  fi

  if grep -q 'kairo_bench exit code: 0' "$SERIAL_LOG"; then
    echo "[kairo-qemu] BENCH SMOKE TEST: PASS"
  elif grep -q 'kairo_bench exit code:' "$SERIAL_LOG"; then
    echo "[kairo-qemu] BENCH SMOKE TEST: FAIL (non-zero exit)"
  else
    echo "[kairo-qemu] BENCH SMOKE TEST: SKIPPED (not run)"
  fi
else
  echo "[kairo-qemu] No serial log found"
fi

echo "[kairo-qemu] === Complete: $RESULTS_DIR ==="
