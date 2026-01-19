#!/bin/sh
set -eu

echo "[disable-zram] Disabling zram swap..."

# Turn swap off if it's enabled
if grep -q '^/dev/zram0 ' /proc/swaps 2>/dev/null; then
  swapoff /dev/zram0 2>/dev/null || true
fi

# Reset zram device (frees RAM used by zram)
if [ -d /sys/block/zram0 ]; then
  echo 1 > /sys/block/zram0/reset 2>/dev/null || true
fi
