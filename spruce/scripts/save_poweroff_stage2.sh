#!/bin/sh

# This script is intended to be copied to /tmp/ at the end of the original
# save_poweroff.sh, and handle the final unmounting of the SD card before
# finally shutting down.
# Use only system binaries — NOT anything on the SD card we're about to unmount.
export PATH=/usr/bin:/usr/sbin:/bin:/sbin
unset LD_LIBRARY_PATH
cd /tmp

# Detach stage2 from inherited stdin/stdout/stderr so it does not
# keep the SD filesystem busy during the final remount.
exec </dev/null >/dev/null 2>&1

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
# Whether init can service `poweroff`/`reboot` at all on this device (see
# device_power_transition_bypasses_init in device.sh). Default off.
FORCE_POWER_TRANSITION="${SPRUCE_FORCE_POWER_TRANSITION:-0}"
# USB Storage Mode export session (App/USBStorageMode/usb_gadget.sh): after
# the clean unmount below, export the card, wait for A or the cable, release,
# then reboot. Default off.
USB_EXPORT="${SPRUCE_USB_EXPORT:-0}"
USB_SESSION_DIR="${USB_SESSION_DIR:-/tmp/usbstorage}"
SYSRQ_CTL="${SPRUCE_SYSRQ_CTL:-/proc/sys/kernel/sysrq}"
SYSRQ_TRIGGER="${SPRUCE_SYSRQ_TRIGGER:-/proc/sysrq-trigger}"
MOUNTINFO="${SPRUCE_MOUNTINFO:-/proc/self/mountinfo}"
SYS_BLOCK="${SPRUCE_SYS_BLOCK:-/sys/block}"

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

# Who still holds the card. Only ever called after a failed clean umount, so
# the cost is irrelevant and the answer is the whole point: without it a
# "clean umount FAILED" line names nothing (SPR-MED-199).
stage2_dump_holders() {
    _re="$(stage2_card_maps_re)"
    echo "stage2: holders of $SD_MOUNTPOINT after the sweep:"
    awk -v mp="$SD_MOUNTPOINT" '$2 ~ "^"mp"(/|$)" {print "  mount " $1 " on " $2}' /proc/mounts 2>/dev/null
    for _pp in /proc/[0-9]*; do
        _pid="${_pp#/proc/}"
        _why=""
        [ "$_pid" = "$$" ] && _why=" (stage2 itself)"
        for _link in cwd exe root; do
            _t=$(readlink "$_pp/$_link" 2>/dev/null) || continue
            case "$_t" in "$SD_MOUNTPOINT" | "$SD_MOUNTPOINT"/*) _why="$_why $_link=$_t" ;; esac
        done
        for _fd in "$_pp"/fd/*; do
            _t=$(readlink "$_fd" 2>/dev/null) || continue
            case "$_t" in "$SD_MOUNTPOINT" | "$SD_MOUNTPOINT"/*) _why="$_why fd=$_t"; break ;; esac
        done
        _m=$(grep -m1 " $SD_MOUNTPOINT/" "$_pp/maps" 2>/dev/null | awk '{print $NF}')
        [ -n "$_m" ] && _why="$_why map=$_m"
        if [ -n "$_re" ]; then
            _m=$(grep -m1 -E " ($_re) " "$_pp/maps" 2>/dev/null | awk '{print $4 "=" $NF}')
            [ -n "$_m" ] && _why="$_why dev-map=$_m"
        fi
        case "$_why" in "" | " (stage2 itself)") ;; *)
            echo "  pid $_pid $(cat "$_pp/comm" 2>/dev/null) $(awk '/^State/{print $2}' "$_pp/status" 2>/dev/null)$_why" ;;
        esac
        # A killed process stuck exiting (in a driver, say) can hold the card with no readable links.
        readlink "$_pp/exe" >/dev/null 2>&1 || continue
        case "$(awk '/^State/{print $2}' "$_pp/status" 2>/dev/null)" in D|Z|X)
            echo "  pid $_pid $(cat "$_pp/comm" 2>/dev/null) exiting/blocked, wchan $(cat "$_pp/wchan" 2>/dev/null)" ;;
        esac
    done
    awk -v mp="$SD_MOUNTPOINT" '$NF ~ "^"mp"/" {print "  unix-socket " $NF}' /proc/net/unix 2>/dev/null
    awk -v mp="$SD_MOUNTPOINT/" 'NR > 1 && index($1, mp) == 1 {print "  swap " $1}' /proc/swaps 2>/dev/null
    stage2_card_loops | while read -r _l _d; do
        echo "  loop /dev/$_l ($_d) <- $(cat "$SYS_BLOCK/$_l/loop/backing_file" 2>/dev/null)"
    done
    stage2_dependent_mounts | sed 's/^/  dependent mount /'
    # What is still alive at all: a holder through a detached mount (an overlay
    # whose upper sits on a card loop) shows no card path anywhere.
    for _pp in /proc/[0-9]*; do
        _e=$(readlink "$_pp/exe" 2>/dev/null) || continue
        echo "  proc ${_pp#/proc/} ppid $(awk '/^PPid/{print $2}' "$_pp/status" 2>/dev/null) $(cat "$_pp/comm" 2>/dev/null) exe=$_e cwd=$(readlink "$_pp/cwd" 2>/dev/null)"
    done
    echo "stage2: end of holders"
}

# True when a path resolves onto the card's device (stock Flip: /data -> userdata,
# which spruce binds from the card). Longest mount prefix wins; the last of equals is on top.
stage2_on_card() {
    _p=$(readlink -f "$1" 2>/dev/null) || return 1
    awk -v p="$_p/" -v mp="$SD_MOUNTPOINT" '
        $2 == mp { card = $1 }
        { m = ($2 == "/") ? "/" : $2 "/"; if (index(p, m) == 1 && length(m) >= best) { best = length(m); src = $1 } }
        END { exit !(card != "" && src == card) }' /proc/mounts
}

# Mirror a line into the kernel log: stock Flips keep it across a warm reboot
# (console-ramoops). <2> so it reaches the console past device_init's printk level 3.
stage2_kmsg() {
    echo "<2>spruce stage2: $*" > /dev/kmsg 2>/dev/null
}

# Wait $1 seconds by the uptime clock. A child exiting ends the busybox shell's own sleep at once:
# after a USB session that cut init's 10 s grace to 0.4 s, and reboot -f preempted BaseOS's rcK.
stage2_wait() {
    _w_end=$(( $(stage2_uptime_cs) + $1 * 100 ))
    while [ "$(stage2_uptime_cs)" -lt "$_w_end" ]; do
        sleep 1
    done
}

# Uptime in hundredths of a second ("1" + the decimals - 100: no octal from a leading zero).
stage2_uptime_cs() {
    read -r _w_up _w_rest < /proc/uptime
    echo $(( ${_w_up%.*} * 100 + 1${_w_up#*.} - 100 ))
}

# Loop devices backed by files on the card, one "loopN major:minor" per line.
stage2_card_loops() {
    for _bf in "$SYS_BLOCK"/loop*/loop/backing_file; do
        [ -e "$_bf" ] || continue
        read -r _f < "$_bf" 2>/dev/null || continue
        case "$_f" in "$SD_MOUNTPOINT"/*) ;; *) continue ;; esac
        _l="${_bf#"$SYS_BLOCK"/}"
        _l="${_l%%/*}"
        echo "$_l $(cat "$SYS_BLOCK/$_l/dev" 2>/dev/null)"
    done
}

# The card's device and its loops' devices as maps prints them (hex major:minor),
# joined for grep -E. Finds files mapped through binds, e.g. the glibc on /usr/lib.
stage2_card_maps_re() {
    {
        awk -v mp="$SD_MOUNTPOINT" '$5 == mp {print $3; exit}' "$MOUNTINFO" 2>/dev/null
        stage2_card_loops | awk '{print $2}'
    } | awk -F: 'NF == 2 {printf "%s%02x:%02x", (n++ ? "|" : ""), $1, $2}'
}

# Mount points that keep the card busy, newest first: mounts inside it, other
# mounts of its device, loop filesystems backed by its files, overlays using it,
# and everything mounted on top of those (by parent id, so same-path binds elsewhere stay).
stage2_dependent_mounts() {
    _loops=" $(stage2_card_loops | awk '{printf "/dev/%s ", $1}')"
    awk -v mp="$SD_MOUNTPOINT" -v dev="$SD_DEV" -v loops="$_loops" '
        {
            id[NR] = $1; par[NR] = $2; mnt[NR] = $5
            for (i = 7; i <= NF; i++) if ($i == "-") break
            fs = $(i + 1); src = $(i + 2); so = $(i + 3)
            if ($5 == mp) next
            if (index($5, mp "/") == 1 || (dev != "" && src == dev) || index(loops, " " src " ") ||
                (fs == "overlay" && (index(so, mp "/") || index(so, "/mnt/sdcard/") || index(so, "/mnt/SDCARD/"))))
                dep[$1] = 1
        }
        END {
            more = 1
            while (more) {
                more = 0
                for (n = 1; n <= NR; n++)
                    if (!(id[n] in dep) && (par[n] in dep)) { dep[id[n]] = 1; more = 1 }
            }
            for (n = NR; n > 0; n--) if (id[n] in dep) print mnt[n]
        }' "$MOUNTINFO" 2>/dev/null
}

if [ "$STRICT_UNMOUNT" = "1" ]; then
    SD_MOUNTPOINT="$(resolve_sd_mountpoint)"
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

# Inherited fds on the card would make this process its own holder. The loop at the
# top skips 10 and up because the shell reads this script through one of those.
if [ "$STRICT_UNMOUNT" = "1" ]; then
    for _fd in /proc/$$/fd/*; do
        _n="${_fd##*/}"
        [ "$_n" -gt 2 ] 2>/dev/null || continue
        case "$(readlink "$_fd" 2>/dev/null)" in "$SD_MOUNTPOINT"/*) eval "exec ${_n}>&-" 2>/dev/null ;; esac
    done
fi

# This process must not pin what it tears down: a dynamic shell maps the libc bound
# from a card loop, and on the BaseOS Flip even a static one runs out of the /usr
# overlay whose upper is a card loop. Re-run under a static copy in /tmp.
# Named busybox: it takes its applet from argv[1] only under that name.
STAGE2_BUSYBOX=/tmp/save_poweroff_stage2/busybox
if [ "$STRICT_UNMOUNT" = "1" ] && [ -z "$STAGE2_STATIC_SHELL" ]; then
    if mkdir -p "${STAGE2_BUSYBOX%/*}" && cp "$SD_MOUNTPOINT/spruce/bin64/busybox" "$STAGE2_BUSYBOX" 2>/dev/null &&
        chmod +x "$STAGE2_BUSYBOX" && "$STAGE2_BUSYBOX" true 2>/dev/null; then
        export STAGE2_STATIC_SHELL="$STAGE2_BUSYBOX"
        exec "$STAGE2_BUSYBOX" sh "$0" "$@"
    fi
fi

# Now that the card's mount point is known, reopen stdout/stderr on a log
# file that is NOT on the card - chosen here rather than above precisely so it
# can be checked against the mount point. On every path, strict or not: a
# shutdown that leaves no trace cannot be told apart from one that never ran,
# and "did the umount succeed" is the one fact the next boot needs
# (SPR-MED-199). /data and /mnt/data are separate partitions under BaseOS,
# /mnt/UDISK is the TrimUI eMMC; /tmp is the fallback and at least survives
# long enough to be read over ssh.
STAGE2_LOG=/tmp/save_poweroff_stage2.log
for _d in /data /mnt/data /mnt/UDISK; do
    case "$_d" in "$SD_MOUNTPOINT"|"$SD_MOUNTPOINT"/*) continue ;; esac
    [ -d "$_d" ] || continue
    stage2_on_card "$_d" && continue
    if touch "$_d/.spruce_shutdown_write_test" 2>/dev/null; then
        rm -f "$_d/.spruce_shutdown_write_test"
        STAGE2_LOG="$_d/spruce_shutdown.log"
        break
    fi
done

# Truncate rather than append: one shutdown per file, so the next boot
# reports the shutdown that just happened and this cannot grow without bound.
exec >"$STAGE2_LOG" 2>&1
echo "=== save_poweroff stage 2, uptime $(cut -d" " -f1 /proc/uptime 2>/dev/null)s, arg=${1:-none} strict=$STRICT_UNMOUNT ==="
echo "stage2: logging to $STAGE2_LOG"
echo "stage2: SD_MOUNTPOINT=$SD_MOUNTPOINT"
if [ -n "$STAGE2_STATIC_SHELL" ]; then
    echo "stage2: re-run under $STAGE2_STATIC_SHELL"
    stage2_kmsg "re-run under $STAGE2_STATIC_SHELL, log $STAGE2_LOG"
fi
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
# The sweep, as a function: the strict path runs it again between umount
# retries, because a holder can appear AFTER the first pass - a watchdog's
# getevent respawned in the instant between its parent being killed and
# the loop reaching it (measured on the Smart Pro S, 2026-09-05: the one
# holder left after the sweep was an orphaned getevent with no card fd).
stage2_kill_holders() {
    if [ "$STRICT_UNMOUNT" = "1" ]; then
        for pid in $(stage2_holder_pids); do
            kill -9 "$pid" 2>/dev/null
        done
        return
    fi

    # The original loop, for devices that have not opted into the strict path:
    # open file descriptors only, one readlink at a time.
    for pidpath in /proc/[0-9]*; do
        pid="${pidpath#/proc/}"

        # Never kill init (pid 1) or ourselves
        [ "$pid" -le 1 ] && continue
        [ "$pid" = "$$" ] && continue

        for fd in "$pidpath/fd/"*; do
            target=$(readlink "$fd" 2>/dev/null) || continue
            case "$target" in
                "$SD_MOUNTPOINT"/*) kill -9 "$pid" 2>/dev/null; break ;;
            esac
        done
    done
}

# Pids holding the card by open fd, cwd, exe or a mapped file. Strict path only.
# One ls and one grep for every process; the loop above forked per process and
# took ~5 s a pass on the Smart Pro S, and it runs at least twice.
stage2_holder_pids() {
    {
        ls -l /proc/[0-9]*/cwd /proc/[0-9]*/exe /proc/[0-9]*/root /proc/[0-9]*/fd/ 2>/dev/null | awk -v mp="$SD_MOUNTPOINT/" -v root="$SD_MOUNTPOINT" '
            /^\/proc\/[0-9]+\/fd\/?:$/ { split($0, a, "/"); cur = a[3]; next }
            / -> / {
                t = $0; sub(/.* -> /, "", t)
                if (index(t, mp) != 1 && t != root) next
                if ($0 ~ / \/proc\/[0-9]+\/(cwd|exe|root) -> /) {
                    p = $0; sub(/.* \/proc\//, "", p); sub(/\/.*/, "", p); print p
                } else {
                    print cur
                }
            }'
        grep -l " $SD_MOUNTPOINT/" /proc/[0-9]*/maps 2>/dev/null | awk -F/ '{print $3}'
        _re="$(stage2_card_maps_re)"
        [ -n "$_re" ] && grep -l -E " ($_re) " /proc/[0-9]*/maps 2>/dev/null | awk -F/ '{print $3}'
    } | sort -un | awk -v self="$$" '$1 > 1 && $1 != self'
}

stage2_kill_holders

# Give the kernel time to close file descriptors from killed processes
sleep 0.1
# Flush all pending writes
sync
# Discover the SD card's block device from its mount entry
SD_DEV=$(awk -v mp="$SD_MOUNTPOINT" '$2 == mp {print $1; exit}' /proc/mounts)

# A swap file on the SD card holds it open for writing until swapoff.
awk -v mp="$SD_MOUNTPOINT/" 'NR > 1 && index($1, mp) == 1 {print $1}' /proc/swaps | \
    while read -r swap; do
    swapoff "$swap" 2>/dev/null
done

# Strict: tear down by mountinfo parentage, newest first, so stacked mounts go
# before their parents; whatever stays busy is detached lazily. Measured on a
# BaseOS Flip (2026-10-17): the steps below left the 32-bit chroot, muOS and ext4 loops.
if [ "$STRICT_UNMOUNT" = "1" ]; then
    for _pass in 1 2 3; do
        stage2_dependent_mounts | while read -r mnt; do umount "$mnt" 2>/dev/null; done
        [ -z "$(stage2_dependent_mounts)" ] && break
        stage2_kill_holders
        sleep 0.2
    done
    _left="$(stage2_dependent_mounts)"
    if [ -n "$_left" ]; then
        echo "stage2: lazily detaching $(echo "$_left" | wc -l) dependent mounts"
        echo "$_left" | while read -r mnt; do umount -l "$mnt" 2>/dev/null; done
    fi
    # A detached loop still holds its backing file on the card: release it, or
    # (while still in use) let the kernel clear it on last close.
    stage2_card_loops | while read -r _l _d; do losetup -d "/dev/$_l" 2>/dev/null; done
else
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
fi
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
        if umount_err=$(umount "$SD_MOUNTPOINT" 2>&1); then
            umount_ok=1
            break
        fi
        umount_tries=$((umount_tries + 1))
        stage2_kill_holders
        sleep 0.3
    done

    if [ "$umount_ok" -eq 1 ]; then
        echo "stage2: unmounted $SD_MOUNTPOINT cleanly after $umount_tries retries"
        stage2_kmsg "unmounted $SD_MOUNTPOINT cleanly after $umount_tries retries"
    else
        echo "stage2: clean umount FAILED after $umount_tries tries, falling back to lazy - filesystem will be left dirty"
        echo "stage2: last umount error: ${umount_err:-none}"
        stage2_kmsg "clean umount FAILED after $umount_tries tries: ${umount_err:-none}"
        stage2_dump_holders | while read -r _l; do echo "$_l"; stage2_kmsg "$_l"; done
        umount -l "$SD_MOUNTPOINT"
    fi
else
    # The original single attempt. Up to three seconds of retries is cheap
    # insurance on a device that needs it and a delay on every shutdown for one
    # that does not.
    if umount "$SD_MOUNTPOINT" 2>/dev/null; then
        umount_ok=1
        echo "stage2: unmounted $SD_MOUNTPOINT cleanly (single attempt)"
    else
        umount_ok=0
        echo "stage2: umount of $SD_MOUNTPOINT FAILED, falling back to lazy - filesystem will be left dirty"
        stage2_dump_holders
        umount -l "$SD_MOUNTPOINT"
    fi
fi

# USB Storage Mode: the card is unmounted and clean, nothing is left that runs
# from it. Export it now and hold here until the user is done; the reboot
# below is the exit. A session that cannot run (nothing staged, card still
# mounted) falls straight through to the reboot rather than exporting.
if [ "$USB_EXPORT" = "1" ]; then
    echo "stage2: USB Storage Mode export session from $USB_SESSION_DIR"
    # A lazy fallback takes the card out of /proc/mounts while its superblock
    # lives on in whatever still holds it - exporting then is the very hazard
    # this session exists to remove. Only a clean umount earns the export.
    if [ "${umount_ok:-0}" != "1" ]; then
        echo "stage2: the card did not unmount cleanly, not exporting it"
    elif [ -f "$USB_SESSION_DIR/usb_gadget.sh" ]; then
        . "$USB_SESSION_DIR/usb_gadget.sh"
        if usb_session_run; then
            echo "stage2: USB session ended, rebooting"
        else
            echo "stage2: USB session did not run (rc=$?), rebooting"
        fi
    else
        echo "stage2: no USB session staged at $USB_SESSION_DIR, rebooting"
    fi
fi

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
elif [ "$1" = "--reboot" ] || [ "$USB_EXPORT" = "1" ]; then
    WANT_REBOOT=1
else
    WANT_REBOOT=0
fi

if [ "$FORCE_POWER_TRANSITION" = "1" ]; then
    # init cannot service the plain applets here (Miniloong: rcS is held by the
    # boot supervisor for the whole session), so `poweroff`/`reboot` would return
    # having done nothing and the 10 s waits below would just be 10 s of a device
    # that looks hung with its card unmounted. Take the filesystems down the
    # REISUB way - enable sysrq, Sync, emergency remount-ro (works on a busy
    # FAT where `mount -o remount,ro` returns EBUSY), Sync - then call the forced
    # form, which is reboot(2) straight to the kernel. Sequence per Jawaka's
    # device_mlp1.c, which measured FAT corruption on this board without it.
    echo 1 > "$SYSRQ_CTL" 2>/dev/null
    sync
    echo s > "$SYSRQ_TRIGGER" 2>/dev/null
    echo u > "$SYSRQ_TRIGGER" 2>/dev/null
    echo s > "$SYSRQ_TRIGGER" 2>/dev/null
    sleep 0.5
    if [ "$WANT_REBOOT" -eq 1 ]; then
        echo "stage2: forced reboot (init does not service power commands on this device)"
        reboot -f
        stage2_wait 3
        echo "stage2: reboot -f did not take, trying sysrq"
        echo b > "$SYSRQ_TRIGGER" 2>/dev/null
    else
        echo "stage2: forced poweroff (init does not service power commands on this device)"
        poweroff -f
        stage2_wait 3
        echo "stage2: poweroff -f did not take, trying sysrq"
        echo o > "$SYSRQ_TRIGGER" 2>/dev/null
    fi
    stage2_wait 5
elif [ "$STRICT_UNMOUNT" != "1" ]; then
    # The original: issue the command and let init take it from there. Every
    # device on this branch has been powering off this way for years, and the
    # escalation below is only worth its risk where the recovery it protects
    # against - a card left read-only by a wedged init - is reachable.
    if [ "$WANT_REBOOT" -eq 1 ]; then
        echo "stage2: rebooting (original path)"
        reboot
    else
        echo "stage2: powering off (original path)"
        poweroff
    fi
    exit 0
else
# sysrq is the last resort below and is commonly left disabled.
echo 1 > "$SYSRQ_CTL" 2>/dev/null

if [ "$WANT_REBOOT" -eq 1 ]; then
    echo "stage2: rebooting"
    reboot
    stage2_wait 10
    echo "stage2: reboot did not take after 10s, forcing"
    stage2_kmsg "reboot did not take after 10s, forcing"
    reboot -f
    stage2_wait 5
    echo "stage2: reboot -f did not take, trying sysrq"
    echo b > "$SYSRQ_TRIGGER" 2>/dev/null
    stage2_wait 5
else
    echo "stage2: powering off"
    poweroff
    stage2_wait 10
    echo "stage2: poweroff did not take after 10s, forcing"
    stage2_kmsg "poweroff did not take after 10s, forcing"
    poweroff -f
    stage2_wait 5
    echo "stage2: poweroff -f did not take, trying sysrq"
    echo o > "$SYSRQ_TRIGGER" 2>/dev/null
    stage2_wait 5
fi
fi

# Still running. Recover rather than leave the user holding a device that cannot
# write to its card: drop the shutdown flag so runtime.sh stops exiting at
# startup and the shim steps aside on its next respawn, and put the card back
# read-write ourselves in case the umount failed and only the remount took.
echo "stage2: every power command failed - recovering so the card is not left read-only"
mount -o remount,rw "$SD_MOUNTPOINT" 2>/dev/null
rm -f /tmp/shutting_down.lock
echo "stage2: recovery done, card should be writable again"