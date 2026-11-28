#!/bin/sh
# Every script wifi.sh runs by absolute path must exist in the repo (/mnt/SDCARD is the repo
# root). wifi.sh once ran /mnt/SDCARD/spruce/scripts/networkservices.sh, which doesn't exist,
# so turning WiFi off never stopped the network services.
script_dir="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$script_dir/../../.." && pwd)"
fail=0
for p in $(grep -o '/mnt/SDCARD/[A-Za-z0-9_./-]*\.sh' "$script_dir/wifi.sh" | sort -u); do
    if [ ! -f "$repo/${p#/mnt/SDCARD/}" ]; then
        echo "FAIL: wifi.sh runs $p, which does not exist"
        fail=1
    fi
done
[ "$fail" = 0 ] && echo "PASS"
exit "$fail"
