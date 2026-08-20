#!/bin/sh

# This script is intended to be copied to /tmp/ at the end of the original
# save_poweroff.sh, and handle the final unmounting of the SD card before
# finally shutting down.
echo 1
# Use only system binaries — NOT anything on the SD card we're about to unmount.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
unset LD_LIBRARY_PATH
echo 2
cd /tmp
echo 3
# Close any file descriptors inherited from save_poweroff.sh that may
# still reference files on the SD card.
for fd in $(ls /proc/$$/fd 2>/dev/null | grep -E '^[3-9][0-9]*$'); do
    eval "exec ${fd}>&-" 2>/dev/null
done

# ...and stdin/stdout/stderr, which that loop deliberately skips. They are
# inherited too, and whatever launched the shutdown decides where they point -
# the menu, the power button watchdog and an ssh session all differ. If any of
# them lands on a file on the card then this script is itself holding the
# filesystem open, and the umount below fails with EBUSY and degrades to a lazy
# one that never marks the filesystem clean. That is what made the failure
# intermittent: it depended on how the shutdown was started, not on anything
# this script does.
#
# Nothing here needs them: progress goes to the console via echo, which is
# pointless once the frontend is dead, and every diagnostic writes to an
# explicit path.
exec </dev/null >/dev/null 2>&1
echo 4
# Where the card is actually mounted.
#
# This used to be guessed from /proc/cpuinfo, which is wrong wherever the mount
# point is a symlink: on BaseOS /mnt/SDCARD is a symlink to /mnt/sdcard, and
# every check below reads /proc/mounts, which always reports the resolved path.
# The guess returned /mnt/SDCARD there, so `$2 == mp` matched no mount line, the
# fd comparison matched no process, and this script killed nothing and unmounted
# nothing while reporting success.
#
# Resolve it instead: take the mount point of the device we were told about,
# preferring the shortest, since the same device can be mounted more than once
# (spruce binds the card's own python onto .../bin/MainUI, which is a second
# entry for the same device - remounting or unmounting that bind is not the
# same as doing it to the filesystem).
#
# $SD_MOUNTPOINT and $SD_DEV are exported by the platform cfg and inherited from
# save_poweroff.sh; the cpuinfo cases are kept only as a last resort for a device
# that somehow reaches here with neither set.
resolve_sd_mountpoint() {
    if [ -n "$SD_DEV" ]; then
        _m=$(awk -v d="$SD_DEV" '$1 == d {print length($2), $2}' /proc/mounts \
            | sort -n | head -1 | cut -d" " -f2-)
        [ -n "$_m" ] && { echo "$_m"; return; }
    fi

    # Fall back to the configured path, resolved through any symlink, but only
    # if the kernel agrees it is a mount point.
    if [ -n "$SD_MOUNTPOINT" ]; then
        _r=$(readlink -f "$SD_MOUNTPOINT" 2>/dev/null)
        if [ -n "$_r" ] && awk -v m="$_r" '$2 == m {found=1} END{exit !found}' /proc/mounts; then
            echo "$_r"; return
        fi
    fi

    INFO=$(cat /proc/cpuinfo 2> /dev/null)
    case $INFO in
        *"TG5050"*)	 echo "/mnt/sdcard/mmcblk1p1" ;;
        *"0xd05"*)   echo "/mnt/sdcard" ;;
        *)           echo "/mnt/SDCARD" ;;
    esac
}

SD_MOUNTPOINT="$(resolve_sd_mountpoint)"
echo "stage2: SD_MOUNTPOINT=$SD_MOUNTPOINT"
echo 5
# Anything that pins the filesystem has to go, or the umount below silently
# degrades to a lazy one: `umount -l` detaches the mount from the namespace, so
# /proc/mounts looks clean, but the superblock lives on until the last reference
# drops - which means fat_put_super never runs and the dirty bit is never
# cleared. It looks exactly like success and is not.
#
# An open file descriptor is only one way to pin it. A process *executing* a
# binary from the card - dropbearmulti, darkhttpd, anything spruce launched -
# holds it through its exe mapping with no fd at all, and a process merely
# sitting in a directory holds it through cwd. Checking only fd/ misses both,
# which is why the plain umount kept failing.
for pidpath in /proc/[0-9]*; do
    pid="${pidpath#/proc/}"

    # Never kill init (pid 1) or ourselves
    [ "$pid" -le 1 ] && continue
    [ "$pid" = "$$" ] && continue

    holds_sd=0

    # cwd and the running executable, neither of which appears under fd/
    for link in "$pidpath/cwd" "$pidpath/exe"; do
        target=$(readlink "$link" 2>/dev/null) || continue
        case "$target" in
            "$SD_MOUNTPOINT"/*) holds_sd=1; break ;;
        esac
    done

    # Then open file descriptors
    if [ "$holds_sd" -eq 0 ]; then
        for fd in "$pidpath/fd/"*; do
            target=$(readlink "$fd" 2>/dev/null) || continue
            case "$target" in
                "$SD_MOUNTPOINT"/*) holds_sd=1; break ;;
            esac
        done
    fi

    [ "$holds_sd" -eq 1 ] && kill -9 "$pid" 2>/dev/null
done

echo 6
# Give the kernel time to close file descriptors from killed processes
sleep 0.1
echo 7
# Flush all pending writes
sync
echo 8
# Discover the SD card's block device from its mount entry
SD_DEV=$(awk -v mp="$SD_MOUNTPOINT" '$2 == mp {print $1; exit}' /proc/mounts)

# Tear down all mounts that depend on the SD card.
# On the Flip, this includes:
#   - ~25 squashfs loop mounts from /mnt/sdcard/spruce/flip/*.sqsh → /usr/lib/*
#   - An overlay on /usr with upperdir on /mnt/SDCARD/Persistent/...
#   - A duplicate mount of the same device at /userdata
# All of these must be removed before the SD card can be cleanly unmounted.
echo 9
# 1. Squashfs loop mounts whose source file is on the SD card
#    (also check /mnt/SDCARD in case of symlinks)
awk '$1 ~ "^/mnt/sdcard/" || $1 ~ "^/mnt/SDCARD/" {print $2}' /proc/mounts | \
    sort -r | while read -r mnt; do
    umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null
done
echo 10
# 2. Overlay filesystems that use the SD card for upper/work dirs
awk '$1 == "overlay" && ($0 ~ "/mnt/sdcard" || $0 ~ "/mnt/SDCARD") {print $2}' /proc/mounts | \
    while read -r mnt; do
    umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null
done
echo 11
# 3. Any other mounts of the same block device (e.g. /userdata)
if [ -n "$SD_DEV" ]; then
    awk -v dev="$SD_DEV" -v mp="$SD_MOUNTPOINT" '$1 == dev && $2 != mp {print $2}' /proc/mounts | \
        sort -r | while read -r mnt; do
        umount "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null
    done
fi
echo 12
# 4. Now remount the SD card read-only (clears the filesystem dirty flag)
#    and perform the final unmount.
mount -o remount,ro "$SD_MOUNTPOINT" 2>/dev/null
sync
# Plain umount first, and say so if it fails. The lazy fallback keeps the boot
# path sane but does NOT flush or mark the filesystem clean, so a shutdown that
# reaches it has not achieved what this script exists for.
# Retry rather than giving up after one attempt. Killing a process with -9 does
# not release its file references synchronously - the kernel tears the process
# down in its own time - so an umount fired immediately after the kill loop can
# fail with EBUSY on holders that are already dying. That timing is why the same
# code produced a clean unmount on one shutdown and a lazy fallback on the next
# with nothing else changed.
#
# The lazy fallback stays as the last resort so the power command is never
# blocked, but it does NOT flush or mark the filesystem clean - it only detaches
# the mount - so reaching it means the card is left dirty and we say so.
umount_tries=0
umount_ok=0
while [ "$umount_tries" -lt 10 ]; do
    if umount "$SD_MOUNTPOINT" 2>/dev/null; then
        umount_ok=1
        break
    fi
    umount_tries=$((umount_tries + 1))
    sleep 0.3
done

if [ "$umount_ok" -eq 1 ]; then
    echo "stage2: unmounted $SD_MOUNTPOINT cleanly after $umount_tries retries"
else
    echo "stage2: clean umount FAILED after $umount_tries tries, falling back to lazy - filesystem will be left dirty"
    umount -l "$SD_MOUNTPOINT"
fi
echo 13

# MM v1-4 require reboot command to power off properly.
if [ -d /customer/app ] && [ ! -e /customer/app/axp_test ]; then
    reboot
elif [ "$1" = "--reboot" ]; then
    reboot
else
    poweroff
fi
echo 14