#!/bin/sh

# This script is intended to be copied to /tmp/ at the end of the original
# save_poweroff.sh, and handle the final unmounting of the SD card before
# finally shutting down.

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
mount -o remount,ro /mnt/SDCARD 2>/dev/null
umount /mnt/SDCARD 2>/dev/null || umount -l /mnt/SDCARD

sync

# MM v1-4 require reboot command to power off properly.
if [ -d /customer/app ] && [ ! -e /customer/app/axp_test ]; then
    reboot
else
    poweroff
fi