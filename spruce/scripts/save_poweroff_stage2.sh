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

# Detach stage2 from inherited stdin/stdout/stderr so it does not
# keep the SD filesystem busy during the final remount.
exec </dev/null >/dev/null 2>&1

echo 3
# Close any file descriptors inherited from save_poweroff.sh that may
# still reference files on the SD card.
for fd in $(ls /proc/$$/fd 2>/dev/null | grep -E '^[3-9][0-9]*$'); do
    eval "exec ${fd}>&-" 2>/dev/null
done

# Everything below that departs from the shutdown spruce shipped for years is
# gated on this. save_poweroff.sh asks the device layer and hands the answer
# over in the environment, because by the time this script runs the card is
# about to go and the device functions are on it.
#
# Default off. This is the last script that runs before the power is cut: a
# device that had a working shutdown keeps exactly the code it had, and opts in
# only once someone has tested the strict path on that hardware.
STRICT_UNMOUNT="${SPRUCE_STRICT_UNMOUNT:-0}"

# ...and stdin/stdout/stderr, which that loop deliberately skips. They are
# inherited too, and whatever launched the shutdown decides where they point -
# the menu, the power button watchdog and an ssh session all differ. If any of
# them lands on a file on the card then this script is itself holding the
# filesystem open, and the umount below fails with EBUSY and degrades to a lazy
# one that never marks the filesystem clean. That is what made the failure
# intermittent: it depended on how the shutdown was started, not on anything
# this script does.
#
# Nothing here needs them, but they must not simply be thrown away either: this
# script sends the device to sleep for good, so if it goes wrong there is no
# session left to ask and nothing on the card to read. Sending everything to
# /dev/null made the whole shutdown unobservable - a report of "power off does
# not work" could not be told apart from "the unmount failed" or "the kill loop
# stalled".
#
# Log to a filesystem that is emphatically NOT the card: an open descriptor
# there is precisely what makes the umount below fail. /data is a separate
# partition under BaseOS and outlives the power cycle, so the next boot can fold
# this into the spruce log and a bug report carries it; /tmp is the fallback and
# at least survives long enough to be read over ssh.
if [ "$STRICT_UNMOUNT" = "1" ]; then
    exec </dev/null >/dev/null 2>&1
fi
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

if [ "$STRICT_UNMOUNT" = "1" ]; then
    SD_MOUNTPOINT="$(resolve_sd_mountpoint)"

    # Now that the card's real mount point is known, reopen stdout/stderr on a
    # log file - chosen here rather than above precisely so it can be checked
    # against the resolved path instead of a configured guess.
    STAGE2_LOG=/tmp/save_poweroff_stage2.log
    for _d in /data /mnt/data; do
        case "$_d" in "$SD_MOUNTPOINT"|"$SD_MOUNTPOINT"/*) continue ;; esac
        [ -d "$_d" ] || continue
        if touch "$_d/.spruce_shutdown_write_test" 2>/dev/null; then
            rm -f "$_d/.spruce_shutdown_write_test"
            STAGE2_LOG="$_d/spruce_shutdown.log"
            break
        fi
    done

    # Truncate rather than append: one shutdown per file, so the next boot
    # reports the shutdown that just happened and this cannot grow without bound.
    exec >"$STAGE2_LOG" 2>&1
    echo "=== save_poweroff stage 2, uptime $(cut -d" " -f1 /proc/uptime 2>/dev/null)s, arg=${1:-none} ==="
    echo "stage2: logging to $STAGE2_LOG"
    echo "stage2: SD_MOUNTPOINT=$SD_MOUNTPOINT"
else
    # The original guess, unchanged. Correct on every device that was shipping
    # this before the XX work: their configured mount point is not behind a
    # symlink, so what cpuinfo returns is what /proc/mounts reports.
    #
    # Flip and TSPS have nonstandard mount points.
    INFO=$(cat /proc/cpuinfo 2> /dev/null)
    case $INFO in
        *"TG5050"*)	 SD_MOUNTPOINT="/mnt/sdcard/mmcblk1p1"	;;
        *"0xd05"*)   SD_MOUNTPOINT="/mnt/sdcard" ;;
        *)           SD_MOUNTPOINT="/mnt/SDCARD" ;;
    esac
fi
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

    # cwd and the running executable, neither of which appears under fd/.
    # Strict mode only: this kills strictly more processes than the original
    # loop did, and on a device whose umount already succeeded that is risk
    # with nothing to buy.
    if [ "$STRICT_UNMOUNT" = "1" ]; then
        for link in "$pidpath/cwd" "$pidpath/exe"; do
            target=$(readlink "$link" 2>/dev/null) || continue
            case "$target" in
                "$SD_MOUNTPOINT"/*) holds_sd=1; break ;;
            esac
        done
    fi

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
if [ "$STRICT_UNMOUNT" = "1" ]; then
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
else
    # The original single attempt. Up to three seconds of retries is cheap
    # insurance on a device that needs it and a delay on every shutdown for one
    # that does not.
    umount "$SD_MOUNTPOINT" 2>/dev/null || umount -l "$SD_MOUNTPOINT"
fi
echo 13

# Cut the power, and do not take "maybe" for an answer.
#
# `poweroff` and `reboot` only signal init and return; init then runs its
# ::shutdown: actions and calls reboot(2). If any part of that wedges, this
# script has already remounted the card read-only and unmounted it, AND every
# path that would normally undo that is deliberately switched off - the
# shutting_down flag makes runtime.sh exit at startup, and the shim keeps
# BaseOS's session from remounting the card. The device is then on, blank, and
# unable to write to its own storage until the user holds the power button.
# "Power off does not work" and "card stuck read-only" are the same failure
# reported twice, so escalate rather than trust the first command.
#
# MM v1-4 require the reboot command to power off properly.
if [ -d /customer/app ] && [ ! -e /customer/app/axp_test ]; then
    WANT_REBOOT=1
elif [ "$1" = "--reboot" ]; then
    WANT_REBOOT=1
else
    WANT_REBOOT=0
fi

if [ "$STRICT_UNMOUNT" != "1" ]; then
    # The original: issue the command and let init take it from there. Every
    # device on this branch has been powering off this way for years, and the
    # escalation below is only worth its risk where the recovery it protects
    # against - a card left read-only by a wedged init - is reachable.
    if [ "$WANT_REBOOT" -eq 1 ]; then
        reboot
    else
        poweroff
    fi
    echo 14
    exit 0
fi

# sysrq is the last resort below and is commonly left disabled.
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null

if [ "$WANT_REBOOT" -eq 1 ]; then
    echo "stage2: rebooting"
    reboot
    sleep 10
    echo "stage2: reboot did not take after 10s, forcing"
    reboot -f
    sleep 5
    echo "stage2: reboot -f did not take, trying sysrq"
    echo b > /proc/sysrq-trigger 2>/dev/null
    sleep 5
else
    echo "stage2: powering off"
    poweroff
    sleep 10
    echo "stage2: poweroff did not take after 10s, forcing"
    poweroff -f
    sleep 5
    echo "stage2: poweroff -f did not take, trying sysrq"
    echo o > /proc/sysrq-trigger 2>/dev/null
    sleep 5
fi

# Still running. Recover rather than leave the user holding a device that cannot
# write to its card: drop the shutdown flag so runtime.sh stops exiting at
# startup and the shim steps aside on its next respawn, and put the card back
# read-write ourselves in case the umount failed and only the remount took.
echo "stage2: every power command failed - recovering so the card is not left read-only"
mount -o remount,rw "$SD_MOUNTPOINT" 2>/dev/null
rm -f /tmp/shutting_down.lock
echo "stage2: recovery done, card should be writable again"