#!/usr/bin/env bash
set -euo pipefail

bool() {
  if "$@"; then
    echo true
  else
    echo false
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

is_wsl=false
if grep -qi microsoft /proc/version 2>/dev/null; then
  is_wsl=true
fi

kernel_release="$(uname -r 2>/dev/null || echo unknown)"
distro="$(
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf '%s\n' "${PRETTY_NAME:-${NAME:-unknown}}"
  else
    echo unknown
  fi
)"

has_tracing_fs=false
[[ -d /sys/kernel/tracing ]] && has_tracing_fs=true

has_sys_block=false
available_block_devices=""
if [[ -d /sys/block ]]; then
  has_sys_block=true
  available_block_devices="$(ls /sys/block 2>/dev/null | paste -sd ',' -)"
fi

default_test_file="/tmp/kairo_validation.bin"
can_write_tmp=false
tmp_probe="/tmp/kairo_validation_write_test.$$"
if : > "$tmp_probe" 2>/dev/null; then
  can_write_tmp=true
  rm -f "$tmp_probe"
fi

echo "is_wsl=$is_wsl"
echo "kernel_release=$kernel_release"
echo "distro=$distro"
echo "has_make=$(bool has_cmd make)"
echo "has_gcc=$(bool has_cmd gcc)"
echo "has_python3=$(bool has_cmd python3)"
echo "has_git=$(bool has_cmd git)"
echo "has_bpftrace=$(bool has_cmd bpftrace)"
echo "has_tracing_fs=$has_tracing_fs"
echo "has_sys_block=$has_sys_block"
echo "available_block_devices=$available_block_devices"
echo "default_test_file=$default_test_file"
echo "can_write_tmp=$can_write_tmp"
