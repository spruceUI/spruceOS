#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh


load_module() {
  module="$1"
  file="$MODULE_DIR/$module.ko"

  grep -qw "^$module" /proc/modules 2>/dev/null && return 0
  [ -f "$file" ] || {
    log_message "Missing ZRAM module: $file"
    return 1
  }

  insmod "$file" 2>/dev/null || true
}

enable_zram="$(get_config_value '.menuOptions."System Settings".useZRAM.selected' "True")"
if [ "$enable_zram" != "True" ]; then
  log_message "No ZRAM requested per user settings."
  /mnt/SDCARD/spruce/scripts/disable_zram.sh
  exit 0
fi

set -eu

# If zram is already active, do nothing
if grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null; then
  exit 0
fi

case "$PLATFORM" in
  "SmartProS")
    MODULE_DIR="/mnt/SDCARD/spruce/smartpros/modules"
    load_module lzo_compress
    load_module lzo
    load_module lzo_rle
    load_module zsmalloc
    load_module zram
    ;;

  "SmartPro"|"Brick"|"BrickPro")
    MODULE_DIR="/mnt/SDCARD/spruce/smartpro/modules"
    load_module zsmalloc
    load_module lzo
    load_module zram
    ;;
  *)
    # Flip / Pixel2: use the kernel's module loader if available.
    if command -v modprobe >/dev/null 2>&1; then
      modprobe zram 2>/dev/null || true
    elif command -v busybox >/dev/null 2>&1; then
      busybox modprobe zram 2>/dev/null || true
    fi
    ;;
esac

# Create zram0 if necessary.
if [ ! -b /dev/zram0 ] && [ -e /sys/class/zram-control/hot_add ]; then
  echo 0 > /sys/class/zram-control/hot_add 2>/dev/null || true
fi

if [ ! -b /dev/zram0 ] || [ ! -d /sys/block/zram0 ]; then
  log_message "zram device not found."
  exit 1
fi

# Reset any previous configuration.
swapoff /dev/zram0 2>/dev/null || true
echo 1 > /sys/block/zram0/reset 2>/dev/null || true

# Select a compressor.
if [ -w /sys/block/zram0/comp_algorithm ]; then
  if grep -qw lz4 /sys/block/zram0/comp_algorithm; then
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
  elif grep -qw lzo /sys/block/zram0/comp_algorithm; then
    echo lzo > /sys/block/zram0/comp_algorithm 2>/dev/null || true
  fi
fi

# 50% of RAM, clamped to 128 MiB - 1 GiB.
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
ZRAM_BYTES=$((MEM_KB * 1024 / 2))
MIN=$((128 * 1024 * 1024))
MAX=$((1024 * 1024 * 1024))

[ "$ZRAM_BYTES" -lt "$MIN" ] && ZRAM_BYTES=$MIN
[ "$ZRAM_BYTES" -gt "$MAX" ] && ZRAM_BYTES=$MAX

echo "$ZRAM_BYTES" > /sys/block/zram0/disksize

if command -v mkswap >/dev/null 2>&1; then
  mkswap /dev/zram0 >/dev/null
else
  busybox mkswap /dev/zram0 >/dev/null
fi

swapon /dev/zram0

[ -w /proc/sys/vm/swappiness ] && echo 60 > /proc/sys/vm/swappiness || true

log_message "ZRAM enabled: $ZRAM_BYTES bytes"