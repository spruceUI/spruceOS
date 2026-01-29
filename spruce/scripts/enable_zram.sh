#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

enable_zram="$(get_config_value '.menuOptions."System Settings".useZRAM.selected' "False")"
if [ "$enable_zram" = "True" ]; then
  log_message "Attempting to enable ZRAM per user settings."
else
  log_message "No ZRAM requested per user settings."
  /mnt/SDCARD/spruce/scripts/disable_zram.sh
  exit 0
fi

set -eu

# If zram is already active, do nothing
if grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null; then
  exit 0
fi

# Load module if possible
if command -v modprobe >/dev/null 2>&1; then
  modprobe zram 2>/dev/null || true
elif command -v busybox >/dev/null 2>&1; then
  busybox modprobe zram 2>/dev/null || true
fi

# Ensure zram0 exists (try hot_add if available)
if [ ! -b /dev/zram0 ] && [ -e /sys/class/zram-control/hot_add ]; then
  echo 0 > /sys/class/zram-control/hot_add 2>/dev/null || true
fi

if [ ! -b /dev/zram0 ] || [ ! -d /sys/block/zram0 ]; then
  log_message "zram device not found (no /dev/zram0). Kernel may lack zram support."
  exit 1
fi

# Reset before changing compressor/disksize (previous run may have initialized it)
swapoff /dev/zram0 2>/dev/null || true
echo 1 > /sys/block/zram0/reset 2>/dev/null || true

# Pick a fast compressor if available (ignore if kernel says busy)
if [ -w /sys/block/zram0/comp_algorithm ]; then
  if grep -qw lz4 /sys/block/zram0/comp_algorithm; then
    log_message "using lz4 compression algorithm"
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null || true
  elif grep -qw lzo /sys/block/zram0/comp_algorithm; then
    log_message "using lzo compression algorithm"
    echo lzo > /sys/block/zram0/comp_algorithm 2>/dev/null || true
  fi
fi

# Size: 40% of RAM, clamped to [128MB, 1024MB]
MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
ZRAM_BYTES=$((MEM_KB * 1024 * 40 / 100))
MIN=$((128 * 1024 * 1024))
MAX=$((1024 * 1024 * 1024))
[ "$ZRAM_BYTES" -lt "$MIN" ] && ZRAM_BYTES=$MIN
[ "$ZRAM_BYTES" -gt "$MAX" ] && ZRAM_BYTES=$MAX

echo "$ZRAM_BYTES" > /sys/block/zram0/disksize
log_message "Using disksize of $ZRAM_BYTES bytes"

# mkswap
if command -v mkswap >/dev/null 2>&1; then
  mkswap /dev/zram0 >/dev/null
else
  busybox mkswap /dev/zram0 >/dev/null
fi

# Enable swap
swapon /dev/zram0

# Swappiness tuning
# Picked 60 as a default
[ -w /proc/sys/vm/swappiness ] && echo 60 > /proc/sys/vm/swappiness || true
