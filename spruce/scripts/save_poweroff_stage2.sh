#!/bin/sh

# This script is intended to be copied to /tmp/ at the end of the original
# save_poweroff.sh, and handle the final unmounting of the SD card before
# finally shutting down.

# Use only system binaries — NOT anything on the SD card we're about to unmount.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
unset LD_LIBRARY_PATH

cd /tmp

# Close any file descriptors inherited from save_poweroff.sh that may
# still reference files on the SD card.
i=3
while [ "$i" -le 50 ]; do
    eval "exec ${i}>&-" 2>/dev/null
    i=$((i + 1))
done

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

# Give the kernel time to close file descriptors from killed processes
sleep 1

# Flush all pending writes
sync
sync

# Discover the SD card's block device from its mount entry
SD_DEV=$(awk -v mp="$SD_MOUNTPOINT" '$2 == mp {print $1; exit}' /proc/mounts)

# Tear down all mounts that depend on the SD card.
# On the Flip, this includes:
#   - ~25 squashfs loop mounts from /mnt/sdcard/spruce/flip/*.sqsh → /usr/lib/*
#   - An overlay on /usr with upperdir on /mnt/SDCARD/Persistent/...
#   - A duplicate mount of the same device at /userdata
# All of these must be removed before the SD card can be cleanly unmounted.

# 1. Squashfs loop mounts whose source file is on the SD card
#    (also check /mnt/SDCARD in case of symlinks)
awk '$1 ~ "^/mnt/sdcard/" || $1 ~ "^/mnt/SDCARD/" {print $2}' /proc/mounts | \
    sort -r | while read -r mnt; do
    umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null
done

# 2. Overlay filesystems that use the SD card for upper/work dirs
awk '$1 == "overlay" && ($0 ~ "/mnt/sdcard" || $0 ~ "/mnt/SDCARD") {print $2}' /proc/mounts | \
    while read -r mnt; do
    umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null
done

# 3. Any other mounts of the same block device (e.g. /userdata)
if [ -n "$SD_DEV" ]; then
    awk -v dev="$SD_DEV" -v mp="$SD_MOUNTPOINT" '$1 == dev && $2 != mp {print $2}' /proc/mounts | \
        sort -r | while read -r mnt; do
        umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null
    done
fi

sync

# 4. Now remount the SD card read-only (clears the filesystem dirty flag)
#    and perform the final unmount.
mount -o remount,ro "$SD_MOUNTPOINT" 2>/dev/null
sync
umount "$SD_MOUNTPOINT" 2>/dev/null || umount -l "$SD_MOUNTPOINT"

sync

# MM v1-4 require reboot command to power off properly.
if [ -d /customer/app ] && [ ! -e /customer/app/axp_test ]; then
    reboot
else
    poweroff
fi
