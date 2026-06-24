#!/usr/bin/env bash
# Build a Linux 6.8.x kernel with Kairo patches for QEMU boot validation.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
LINUX_DIR="${LINUX_DIR:-$HOME/linux-6.8}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"

usage() {
  cat <<'EOF'
Usage:
  ./kernel/integration/linux-6.8/build_kairo_qemu_kernel.sh [--linux-dir DIR] [--jobs N]

Builds a Linux 6.8.x kernel with Kairo patches applied, configured for QEMU boot.

Options:
  --linux-dir DIR    Path to Linux 6.8 source (default: .linux-6.8 in repo root)
  --jobs N           Parallel make jobs (default: nproc)
  --help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --linux-dir) LINUX_DIR="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ ! -d "$LINUX_DIR" ]]; then
  echo "[kairo-qemu] Linux 6.8 source not found at $LINUX_DIR"
  echo "[kairo-qemu] Cloning linux-6.8.y from kernel.org..."
  git clone --depth 1 --branch linux-6.8.y \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git \
    "$LINUX_DIR"
fi

cd "$LINUX_DIR"

# Apply all Kairo patches in order (0001-0030)
echo "[kairo-qemu] Applying Kairo patches..."
shopt -s nullglob
KAIRO_PATCHES=("$REPO_ROOT/kernel/patches/"0*.patch)
shopt -u nullglob
for p in "${KAIRO_PATCHES[@]}"; do
  if [[ -f "$p" ]]; then
    echo "[kairo-qemu]   applying $(basename "$p")"
    if ! git apply --reject --ignore-whitespace "$p" 2>&1; then
      echo "[kairo-qemu]   conflict, skipping $(basename "$p")"
      git checkout -- . 2>/dev/null || true
      git reset HEAD 2>/dev/null || true
    fi
  fi
done
# Commit the combined patch set
git add -A && git commit -m "Kairo patches applied" 2>/dev/null || true

# Generate minimal QEMU-friendly .config
echo "[kairo-qemu] Generating kernel config..."
if [[ ! -f .config ]]; then
  make ARCH=x86_64 defconfig
fi

# Enable Kairo-relevant options and QEMU boot essentials
./scripts/config \
  --enable CONFIG_BLOCK \
  --enable CONFIG_BLK_DEV_INTEGRITY \
  --enable CONFIG_MQ_IOSCHED_DEADLINE \
  --enable CONFIG_IOSCHED_MQ_DEADLINE \
  --enable CONFIG_BLK_CGROUP \
  --enable CONFIG_BLK_CGROUP_IOLATENCY \
  --enable CONFIG_BLK_CGROUP_FC_APPID \
  --enable CONFIG_BLK_DEBUG_FS \
  --enable CONFIG_BLK_WBT \
  --enable CONFIG_BLK_WBT_MQ \
  --enable CONFIG_VIRTIO \
  --enable CONFIG_VIRTIO_BLK \
  --enable CONFIG_VIRTIO_CONSOLE \
  --enable CONFIG_VIRTIO_NET \
  --enable CONFIG_EXT4_FS \
  --enable CONFIG_EXT4_FS_POSIX_ACL \
  --enable CONFIG_PROC_FS \
  --enable CONFIG_SYSFS \
  --enable CONFIG_TMPFS \
  --enable CONFIG_DEVTMPFS \
  --enable CONFIG_DEVTMPFS_MOUNT \
  --enable CONFIG_SERIAL_8250 \
  --enable CONFIG_SERIAL_8250_CONSOLE \
  --enable CONFIG_PRINTK \
  --enable CONFIG_DYNAMIC_DEBUG \
  --enable CONFIG_NET \
  --enable CONFIG_INET \
  --enable CONFIG_IPV6 \
  --enable CONFIG_BINFMT_ELF \
  --enable CONFIG_BINFMT_SCRIPT \
  --enable CONFIG_IA32_EMULATION \
  --enable CONFIG_OVERLAY_FS \
  --enable CONFIG_SQUASHFS \
  --enable CONFIG_BLK_DEV_NVME \
  --enable CONFIG_NVME_CORE \
  --enable CONFIG_NVME_MULTIPATH \
  || true

# Disable modules to avoid module install complexity
./scripts/config --disable CONFIG_MODULES 2>/dev/null || true

# Build kernel
echo "[kairo-qemu] Building kernel with $JOBS jobs..."
make ARCH=x86_64 -j"$JOBS" bzImage 2>&1 | tail -20

echo "[kairo-qemu] Kernel built: arch/x86_64/boot/bzImage"
ls -lh arch/x86_64/boot/bzImage
