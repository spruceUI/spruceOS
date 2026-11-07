#!/bin/sh

# Runs from /tmp to unmount the SD card and finish shutdown.
# Use system binaries only; the card will be unmounted.
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

# New shutdown paths are opt-in; defaults preserve existing behavior.
STRICT_UNMOUNT="${SPRUCE_STRICT_UNMOUNT:-0}"
# Whether init handles power commands on this device. Default off.
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

# In strict mode, detach inherited streams before logging: they may point to
# the card and prevent unmounting. Keep logs on another filesystem.
if [ "$STRICT_UNMOUNT" = "1" ]; then
    exec </dev/null >/dev/null 2>&1
fi
# Resolve the card's actual mount point from its device, preferring the shortest
# match because the same device may also have bind mounts. Fall back to the
# configured path, then cpuinfo for older callers without exported values.
resolve_sd_mountpoint() {
    if [ -n "$SD_DEV" ]; then
        _m=$(awk -v d="$SD_DEV" '$1 == d {print length($2), $2}' /proc/mounts \
            | sort -n | head -1 | cut -d" " -f2-)
        [ -n "$_m" ] && { echo "$_m"; return; }
    fi

    # Resolve symlinks and accept the path only if it is a mount point.
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

# Report remaining card holders when a clean unmount fails.
stage2_dump_holders() {
    _re="$(stage2_card_maps_re)"
    echo "stage2: holders of $SD_MOUNTPOINT after the sweep:"
    awk -v mp="$SD_MOUNTPOINT" '$2 ~ "^"mp"(/|$)" {print "  mount " $1 " on " $2}' /proc/mounts 2>/dev/null
    echo "  dependent mount ids: ${STAGE2_DEP_IDS:-none}"
    _ids="$(echo $STAGE2_DEP_IDS | tr ' ' '|')"
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
        if [ -n "$_ids" ]; then
            _m=$(grep -l -E "^mnt_id:[[:space:]]+($_ids)\$" "$_pp"/fdinfo/* 2>/dev/null | head -1)
            [ -n "$_m" ] && _why="$_why dep-mnt-fd=$(readlink "$_pp/fd/${_m##*/}" 2>/dev/null)"
        fi
        case "$_why" in "" | " (stage2 itself)") ;; *)
            echo "  pid $_pid $(cat "$_pp/comm" 2>/dev/null) $(awk '/^State/{print $2}' "$_pp/status" 2>/dev/null)$_why" ;;
        esac
        # Blocked or exiting processes may still hold the card without visible links.
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
    # Include live processes that hold the card through detached mounts.
    for _pp in /proc/[0-9]*; do
        _e=$(readlink "$_pp/exe" 2>/dev/null) || continue
        echo "  proc ${_pp#/proc/} ppid $(awk '/^PPid/{print $2}' "$_pp/status" 2>/dev/null) $(cat "$_pp/comm" 2>/dev/null) exe=$_e cwd=$(readlink "$_pp/cwd" 2>/dev/null)"
    done
    echo "stage2: end of holders"
}

# True if a path resolves to the card's device. The longest mount prefix wins.
stage2_on_card() {
    _p=$(readlink -f "$1" 2>/dev/null) || return 1
    awk -v p="$_p/" -v mp="$SD_MOUNTPOINT" '
        $2 == mp { card = $1 }
        { m = ($2 == "/") ? "/" : $2 "/"; if (index(p, m) == 1 && length(m) >= best) { best = length(m); src = $1 } }
        END { exit !(card != "" && src == card) }' /proc/mounts
}

# Mirror lines to the kernel log, which survives warm reboot on stock Flip.
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

# Uptime in hundredths of a second, avoiding octal parsing of leading zeros.
stage2_uptime_cs() {
    read -r _w_up _w_rest < /proc/uptime
    echo $(( ${_w_up%.*} * 100 + 1${_w_up#*.} - 100 ))
}

# tasks/repairSD.sh keeps copies of the card helpers below for the SD card repair; change both together.

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

# Regex of the card and loop device IDs, as shown in process maps.
stage2_card_maps_re() {
    {
        awk -v mp="$SD_MOUNTPOINT" '$5 == mp {print $3; exit}' "$MOUNTINFO" 2>/dev/null
        stage2_card_loops | awk '{print $2}'
    } | awk -F: 'NF == 2 {printf "%s%02x:%02x", (n++ ? "|" : ""), $1, $2}'
}

# Card-dependent mount points, newest first, including stacked mounts.
stage2_dependent_mounts() {
    _loops=" $(stage2_card_loops | awk '{printf "/dev/%s ", $1}')"
    awk -v mp="$SD_MOUNTPOINT" -v dev="$SD_DEV" -v loops="$_loops" -v what="$1" '
        {
            id[NR] = $1; par[NR] = $2; mnt[NR] = $5
            for (i = 7; i <= NF; i++) if ($i == "-") break
            fs = $(i + 1); src = $(i + 2); so = $(i + 3)
            if ($5 == mp) { card = $1; next }
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
            for (n = NR; n > 0; n--) if (id[n] in dep) print (what == "ids" ? id[n] : mnt[n])
            if (what == "ids" && card != "") print card
        }' "$MOUNTINFO" 2>/dev/null
}

# Find processes whose executable or cwd belongs to a dependent mount.
stage2_link_mnt_pids() {
    for _pp in /proc/[0-9]*; do
        for _link in exe cwd; do
            _mid=""
            { while read -r _k _v; do [ "$_k" = "mnt_id:" ] && { _mid=$_v; break; }; done < /proc/self/fdinfo/9; } 2>/dev/null 9< "$_pp/$_link"
            [ -n "$_mid" ] && case " $STAGE2_DEP_IDS " in *" $_mid "*) echo "${_pp#/proc/}"; break ;; esac
        done
    done
}

if [ "$STRICT_UNMOUNT" = "1" ]; then
    SD_MOUNTPOINT="$(resolve_sd_mountpoint)"
else
    # Preserve the legacy cpuinfo-based mount-point selection.
    INFO=$(cat /proc/cpuinfo 2> /dev/null)
    case $INFO in
        *"TG5050"*)	 SD_MOUNTPOINT="/mnt/sdcard/mmcblk1p1"	;;
        *"0xd05"*)   SD_MOUNTPOINT="/mnt/sdcard" ;;
        *)           SD_MOUNTPOINT="/mnt/SDCARD" ;;
    esac
fi

# Close inherited card fds so this process does not hold the mount open.
if [ "$STRICT_UNMOUNT" = "1" ]; then
    for _fd in /proc/$$/fd/*; do
        _n="${_fd##*/}"
        [ "$_n" -gt 2 ] 2>/dev/null || continue
        case "$(readlink "$_fd" 2>/dev/null)" in "$SD_MOUNTPOINT"/*) eval "exec ${_n}>&-" 2>/dev/null ;; esac
    done
fi

# Re-run from a static BusyBox copy in /tmp so this process does not pin the card
# through its shell, libraries, or the BaseOS /usr overlay.
STAGE2_BUSYBOX=/tmp/save_poweroff_stage2/busybox
if [ "$STRICT_UNMOUNT" = "1" ] && [ -z "$STAGE2_STATIC_SHELL" ]; then
    if mkdir -p "${STAGE2_BUSYBOX%/*}" && cp "$SD_MOUNTPOINT/spruce/bin64/busybox" "$STAGE2_BUSYBOX" 2>/dev/null &&
        chmod +x "$STAGE2_BUSYBOX" && "$STAGE2_BUSYBOX" true 2>/dev/null; then
        export STAGE2_STATIC_SHELL="$STAGE2_BUSYBOX"
        exec "$STAGE2_BUSYBOX" sh "$0" "$@"
    fi
fi

# Log off-card so the descriptor cannot block unmounting; use /tmp if no
# separate writable filesystem is available.
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
# Kill processes holding the card through open files, cwd, or executable
# mappings; otherwise unmount may fall back to lazy detach and leave it dirty.
# Strict mode repeats the sweep between retries to catch newly spawned holders.
stage2_kill_holders() {
    if [ "$STRICT_UNMOUNT" = "1" ]; then
        # Logged even when the umount then succeeds: which processes held the card.
        _swept=""
        for pid in $(stage2_holder_pids); do
            _comm=""; { read -r _comm < "/proc/$pid/comm"; } 2>/dev/null
            _swept="$_swept $pid:$_comm"
            kill -9 "$pid" 2>/dev/null
        done
        [ -n "$_swept" ] && echo "stage2: swept holders:$_swept"
        return
    fi

    # The original loop, for devices that have not opted into the strict path:
    # open file descriptors only, one readlink at a time.
    for pidpath in /proc/[0-9]*; do
        pid="${pidpath#/proc/}"

        # Never kill init or this script.
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

# Find strict-mode holders by fd, cwd, executable, or mapped file.
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
        # Dependent mounts may expose only their mount ID, not a card path.
        if [ -n "$STAGE2_DEP_IDS" ]; then
            grep -l -E "^mnt_id:[[:space:]]+($(echo $STAGE2_DEP_IDS | tr ' ' '|'))\$" /proc/[0-9]*/fdinfo/* 2>/dev/null | awk -F/ '{print $3}'
            stage2_link_mnt_pids
        fi
    } | sort -un | awk -v self="$$" '$1 > 1 && $1 != self'
}

# Mount ids of what depends on the card: stage 1's (taken before its unmount_all lazily detached the busy ones,
# which left mountinfo) and what is still mounted. A holder through spruce's /usr overlay has only that id.
[ "$STRICT_UNMOUNT" = "1" ] && STAGE2_DEP_IDS="$SPRUCE_CARD_MNT_IDS $(stage2_dependent_mounts ids | tr '\n' ' ')"

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

# Strict mode removes dependent mounts newest-first, then lazily detaches any
# remaining mounts and releases their loop devices.
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
# Legacy teardown of mounts backed by or sharing the SD card.
# 1. Loop mounts whose source is on the card.
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
# 4. Remount read-only to clear the dirty flag, then unmount.
mount -o remount,ro "$SD_MOUNTPOINT" 2>/dev/null
sync
# Retry clean unmounts because killed processes may still be releasing file
# references. Lazy detach is only a fallback; it does not mark the card clean.
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
    # Preserve the legacy single-attempt behavior.
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

# Export only after a clean unmount; the USB session blocks until exit, then
# shutdown reboots the device.
if [ "$USB_EXPORT" = "1" ]; then
    echo "stage2: USB Storage Mode export session from $USB_SESSION_DIR"
    # Never export after lazy detach; the card may still be in use.
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

# Escalate if the power command fails: the card is already unmounted, and the
# shutdown flags prevent the normal session from restoring it.
# MM v1-4 require reboot to power off.
if [ -d /customer/app ] && [ ! -e /customer/app/axp_test ]; then
    WANT_REBOOT=1
elif [ "$1" = "--reboot" ] || [ "$USB_EXPORT" = "1" ]; then
    WANT_REBOOT=1
else
    WANT_REBOOT=0
fi

if [ "$FORCE_POWER_TRANSITION" = "1" ]; then
    # Init cannot service power commands here. Use sysrq to sync and remount
    # filesystems, then force the requested power transition.
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
    # Preserve the original init-managed power transition.
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

# If all power commands fail, restore write access and clear the shutdown flag.
echo "stage2: every power command failed - recovering so the card is not left read-only"
mount -o remount,rw "$SD_MOUNTPOINT" 2>/dev/null
rm -f /tmp/shutting_down.lock
echo "stage2: recovery done, card should be writable again"