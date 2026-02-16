#!/bin/sh

# This script is intended to be copied to /tmp/ at the end of the original
# save_poweroff.sh, and handle the final unmounting of the SD card before
# finally shutting down.

cd /tmp

# Flip and TSPS have nonstandard mount points.
INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"TG5050"*)	 SD_MOUNTPOINT="/mnt/sdcard/mmcblk1p1"	;;
    *"0xd05"*)   SD_MOUNTPOINT="/mnt/sdcard" ;;
    *)           SD_MOUNTPOINT="/mnt/SDCARD" ;;
esac



# Kill all remaining userspace processes except init and ourselves
for pidpath in /proc/[0-9]*; do
    pid="${pidpath#/proc/}"

    # Never kill init (pid 1) or ourselves
    [ "$pid" -le 1 ] && continue
    [ "$pid" = "$$" ] && continue

    # Skip kernel threads (empty cmdline)
    if ! tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q .; then
        continue
    fi

    kill -9 "$pid" 2>/dev/null
done

sleep 0.2
sync

# Final SD unmount (lazy fallback allowed)
mount -o remount,ro "$SD_MOUNTPOINT" 2>/dev/null
umount "$SD_MOUNTPOINT" 2>/dev/null || umount -l "$SD_MOUNTPOINT"

sync

# MM v1-4 require reboot command to power off properly.
if [ -d /customer/app ] && [ ! -e /customer/app/axp_test ]; then
    reboot
else
    poweroff
fi