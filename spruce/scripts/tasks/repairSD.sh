#!/bin/sh

# TODO: opt out with a tmp_confirm() ?

EXPERT_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/expertappswitch.png"
TMP_LOG_PATH=/tmp/SDCARD_REPAIR.log
FINAL_LOG_PATH="/mnt/SDCARD/SDCARD_REPAIR.log"
FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"
SDFIX_DIR=/tmp/sdfix
# The kernel's tables and BaseOS's splash, through variables so the tests can point them at fixtures.
MOUNTINFO="${SDFIX_MOUNTINFO:-/proc/self/mountinfo}"
PROC="${SDFIX_PROC:-/proc}"
SYS_BLOCK="${SDFIX_SYS_BLOCK:-/sys/block}"
BASEOS_SPLASH="${SDFIX_BASEOS_SPLASH:-/usr/bin/baseos-splash}"


  ##################
##### SETTING UP #####
  ##################

if [ -z "$1" ]; then
    . "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

    read_only_check

    msg="The SD card repair utility will require a reboot, and may take a while to complete. Press B to cancel, or press A to begin the repair process."
    if [ "$PLATFORM" = "A30" ]; then
        msg="$msg If you choose to run the utility, your device will shut itself down, after which you will need to manually power it back on in order to continue."
    else
        msg="$msg If you choose to run the utility, your device will reboot and begin the repair process."
    fi

    start_pyui_message_writer 
    display_image_and_text "$EXPERT_ICON" 35 5 "$msg" 45
    if confirm 60; then
        log_message "User confirmed running repairSD.sh."
        touch /mnt/SDCARD/FIX_MY_SDCARD
        sync
        [ "$PLATFORM" = "A30" ] && poweroff || reboot
    else
        log_message "User declined running repairSD.sh."
        exit 1
    fi
fi



  ########################
##### HELPER FUNCTIONS #####
  ########################

resolve_platform_facts() {
    if [ -z "$PLATFORM" ] || [ -z "$SD_MOUNTPOINT" ]; then
        . /mnt/SDCARD/spruce/scripts/helperFunctions.sh
    fi

    SD_MOUNTPOINT="${SD_MOUNTPOINT:-/mnt/SDCARD}"

    # The node is not fixed: dArkMoss follows probe order, and BaseOS mounts TF1's
    # mmcblk0p7 when no TF2 is fitted, while the XX cfg names mmcblk1p1 either way.
    _mount_path=$(readlink -f "$SD_MOUNTPOINT" 2>/dev/null)
    [ -n "$_mount_path" ] || _mount_path="$SD_MOUNTPOINT"
    _mounted_dev=$(awk -v mp="$_mount_path" '$2==mp {print $1; exit}' /proc/mounts 2>/dev/null)
    if [ -n "$_mounted_dev" ]; then
        SD_DEV="$_mounted_dev"
        CARD_MP="$_mount_path"
    fi

    DISPLAY_WIDTH="${DISPLAY_WIDTH:-640}"
    DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-480}"
    DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"

    case "$DISPLAY_TEXT_ELF_WIDTH" in
        ''|*[!0-9]*) TEXT_WIDTH=$((DISPLAY_WIDTH - 80)) ;;
        *)           TEXT_WIDTH="$DISPLAY_TEXT_ELF_WIDTH" ;;
    esac

    BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
    [ "$DISPLAY_WIDTH" -ge 1280 ] 2>/dev/null &&
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png"

    BIN_DIR="/mnt/SDCARD/spruce/bin64"
    if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
        BIN_DIR="/mnt/SDCARD/spruce/bin"
    fi
}

strip_card_paths() {
    _out=""
    _old_ifs="$IFS"
    IFS=:
    for _d in $1; do
        case "$_d" in ""|/mnt/SDCARD*|/mnt/sdcard*) continue ;; esac
        _out="${_out:+$_out:}$_d"
    done
    IFS="$_old_ifs"
    echo "$_out"
}

stage_repair_tools() {
    mkdir -p "$SDFIX_DIR"

    cp "$FONT" "$SDFIX_DIR/font.ttf" && echo "staged font"
    cp "$BG_IMAGE" "$SDFIX_DIR/bg.png" && echo "staged background"
    cp "$EXPERT_ICON" "$SDFIX_DIR/" && echo "staged icon"

    if cp "$BIN_DIR/display_text.elf" "$SDFIX_DIR/"; then
        chmod 777 "$SDFIX_DIR/display_text.elf"
        echo "staged display_text.elf from $BIN_DIR"
    fi

    FSCK_BIN="$(command -v fsck.fat 2>/dev/null)"
    if [ -n "$FSCK_BIN" ]; then
        echo "using the base system's fsck.fat at $FSCK_BIN"
    elif cp "$BIN_DIR/fsck.fat" "$SDFIX_DIR/"; then
        chmod 777 "$SDFIX_DIR/fsck.fat"
        FSCK_BIN="$SDFIX_DIR/fsck.fat"
        echo "staged fsck.fat from $BIN_DIR"
    fi
}

tmp_blink() {
    if [ "$PLATFORM" = "A30" ]; then
        echo heartbeat > /sys/devices/platform/sunxi-led/leds/led1/trigger
    elif [ "$PLATFORM" = "Flip" ]; then
        echo heartbeat > /sys/class/leds/work/trigger
    else
        [ -d /sys/class/led_anim ] || return 0     # TrimUI's; a failed redirect isn't silenced
        zones="l r m f1 f2"
        effect=2           # breathe
        color="FF0000"     # red
        duration=1500      # 1000 ms
        cycles=-1          # infinite

        # Enable LED effects globally
        echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null

        # Apply to all zones
        for zone in $zones; do
            echo "$color" > /sys/class/led_anim/effect_rgb_hex_$zone 2>/dev/null
            echo "$cycles" > /sys/class/led_anim/effect_cycles_$zone 2>/dev/null
            echo "$duration" > /sys/class/led_anim/effect_duration_$zone 2>/dev/null
            echo "$effect" > /sys/class/led_anim/effect_$zone 2>/dev/null
        done
    fi
}

tmp_debug_info() {
    echo ""
    echo "DEBUG"
    echo ""

    echo "ps:"
    echo ""
    ps
    echo ""

    echo "mount:"
    echo ""
    mount
    echo ""

}

# Best effort: the Mini stubs display() out, and the RGB30's display_text.elf
# dies at SDL_CreateWindow on its Mali blob. On BaseOS it runs, but nothing it draws reaches the
# panel, even with the SDL2 PyUI draws with, so BaseOS's own splash shows the short text ($2)
# instead: one line, none narrower than the last, whose pill edges would show.
tmp_display() {
    tmp_display_kill

    if [ -n "$2" ] && [ -x "$BASEOS_SPLASH" ] && "$BASEOS_SPLASH" --important -1 "$2"; then
        echo "splash: $2"
        return 0
    fi

    [ -x "$SDFIX_DIR/display_text.elf" ] || { echo "no display tool staged: $1"; return 0; }

    "$SDFIX_DIR/display_text.elf" \
        "$DISPLAY_WIDTH" "$DISPLAY_HEIGHT" "$DISPLAY_ROTATION" \
        "$SDFIX_DIR/bg.png" "$1" 0 30 50 middle "$TEXT_WIDTH" \
        eb db b2 "$SDFIX_DIR/font.ttf" 7f 7f 7f 0 1.0 \
        >>"$SDFIX_DIR/display.out" 2>&1 &
    DISPLAY_PID=$!

    sleep 0.5
    if kill -0 "$DISPLAY_PID" 2>/dev/null; then
        echo "displaying: $1"
    else
        echo "display exited at once (unsupported on this device?): $(tail -1 "$SDFIX_DIR/display.out" 2>/dev/null)"
    fi
}

tmp_display_kill() {
    [ -n "$DISPLAY_PID" ] && kill "$DISPLAY_PID" 2>/dev/null
    sleep 0.1
}

# dArkMoss's spruce-launch.service is Restart=on-failure with a mount in
# ExecStartPre, so it remounts the card 3s after runtime.sh is killed below.
tmp_stop_frontend_service() {
    command -v systemctl >/dev/null 2>&1 || return 0
    if systemctl stop spruce-launch.service 2>/dev/null; then
        echo "Stopped spruce-launch.service so it cannot remount the card."
    fi
}

# Whatever restarts the boot chain once it is killed (BaseOS's init, the boot session supervisor)
# must not start spruce again under fsck's feet. Use the shutdown's guard: the shutting_down flag
# makes a restarted runtime.sh exit at once and the supervisor stand down. BaseOS's session script
# would also mount the card again; the shield device_init puts over it (not there yet at this
# point of the boot) waits while the flag exists. The flag lives in /tmp, which the reboot or
# power-off clears.
tmp_hold_off_respawns() {
    touch /tmp/shutting_down.lock
    _shield=/mnt/SDCARD/spruce/scripts/platform/device_functions/utils/baseos_session_shield.sh
    [ -f "$_shield" ] || return 0
    command -v log_message >/dev/null 2>&1 || log_message() { echo "$1"; }
    . "$_shield"
    shield_baseos_session /sbin/frontend-session
    shield_baseos_session /sbin/nextui-session
}

# By name first, in this order: the Miyoo Mini's stock main deletes .tmp_update if it outlives
# updater. Whatever else holds the card goes in repair_release_card.
tmp_kill_boot_scripts() {
    echo "Attempting to kill any boot scripts."
    for script in runtime.sh principal.sh MainUI main tee runmiyoo.sh runtrimui.sh \
        runmagicx.sh updater menubutton_watchdog.sh buttons_watchdog.sh idlemon \
        idle_watchdog.sh battery_level_watchdog.sh theme_watchdog.sh volume_sync_watchdog.sh \
        inotifywait inotifywatch getevent sendevent ; do
        if killall -9 "$script" ; then
            echo "Killed ${script}."
        fi
        sleep 0.1
    done
}

  ######################
##### RELEASING THE CARD #####
  ######################

# Loop devices backed by files on the card, one "loopN major:minor" per line.
card_loops() {
    [ -n "$CARD_MP" ] || return 0
    for _bf in "$SYS_BLOCK"/loop*/loop/backing_file; do
        [ -e "$_bf" ] || continue
        read -r _f < "$_bf" 2>/dev/null || continue
        case "$_f" in "$CARD_MP"/*) ;; *) continue ;; esac
        _l="${_bf#"$SYS_BLOCK"/}"
        _l="${_l%%/*}"
        echo "$_l $(cat "$SYS_BLOCK/$_l/dev" 2>/dev/null)"
    done
}

# What keeps the card mounted, newest first: mounts inside it, other mounts of its device (binds
# of card files over /etc and the like), filesystems on loops backed by its files, overlays using
# it, and whatever is mounted on top of those. Not the card's own mount.
card_dependent_mounts() {
    [ -n "$CARD_MP" ] || return 0
    _loops=" $(card_loops | awk '{printf "/dev/%s ", $1}')"
    awk -v mp="$CARD_MP" -v dev="$SD_DEV" -v loops="$_loops" '
        {
            id[NR] = $1; par[NR] = $2; mnt[NR] = $5
            for (i = 7; i <= NF; i++) if ($i == "-") break
            fs = $(i + 1); src = $(i + 2); so = $(i + 3)
            if ($5 == mp) next
            if (index($5, mp "/") == 1 || src == dev || index(loops, " " src " ") ||
                (fs == "overlay" && index(so, mp "/")))
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

# True while any mount of the card's device is left (a bind is the same filesystem), and when
# the mount table cannot be read: fsck must never write to a mounted card.
card_is_mounted() {
    [ -r "$MOUNTINFO" ] || return 0
    awk -v dev="$SD_DEV" '
        { for (i = 7; i <= NF; i++) if ($i == "-") break; if ($(i + 2) == dev) found = 1 }
        END { exit !found }' "$MOUNTINFO"
}

# The card's device and its loops' devices as /proc/<pid>/maps prints them (hex major:minor),
# joined for grep -E: finds files mapped from the card whatever path they were opened by.
card_maps_re() {
    {
        awk -v mp="$CARD_MP" '$5 == mp {print $3; exit}' "$MOUNTINFO" 2>/dev/null
        card_loops | awk '{print $2}'
    } | awk -F: 'NF == 2 {printf "%s%02x:%02x", (n++ ? "|" : ""), $1, $2}'
}

# Pids holding the card: an open file, working directory, executable, root or mapped file on it,
# through any of its mount points. Not init, and not this script or its own children (the scan's
# pipeline, the display tool), which would only hold the card if started with its library path.
repair_holder_pids() {
    [ -n "$CARD_MP" ] || return 0
    _re="$(card_maps_re)"
    {
        ls -l "$PROC"/[0-9]*/cwd "$PROC"/[0-9]*/exe "$PROC"/[0-9]*/root "$PROC"/[0-9]*/fd/ 2>/dev/null |
            awk -v mi="$MOUNTINFO" -v dev="$SD_DEV" -v mp="$CARD_MP" '
                BEGIN {
                    roots[mp] = 1
                    while ((getline line < mi) > 0) {
                        n = split(line, f, " ")
                        for (i = 7; i <= n; i++) if (f[i] == "-") break
                        if (f[i + 2] == dev) roots[f[5]] = 1
                    }
                }
                /\/fd\/?:$/ { h = $0; sub(/\/fd\/?:$/, "", h); n = split(h, a, "/"); cur = a[n]; next }
                / -> / {
                    t = $0; sub(/.* -> /, "", t)
                    on = 0
                    for (r in roots) if (t == r || index(t, r "/") == 1) on = 1
                    if (!on) next
                    for (i = 1; i < NF; i++) if ($i == "->") break
                    name = $(i - 1)
                    if (name ~ /\/(cwd|exe|root)$/) {
                        sub(/\/(cwd|exe|root)$/, "", name); n = split(name, a, "/"); print a[n]
                    } else print cur
                }'
        grep -l -F " $CARD_MP/" "$PROC"/[0-9]*/maps 2>/dev/null | awk -F/ '{print $(NF - 1)}'
        [ -n "$_re" ] && grep -l -E " ($_re) " "$PROC"/[0-9]*/maps 2>/dev/null | awk -F/ '{print $(NF - 1)}'
    } | sort -un | while read -r _pid; do
        [ "$_pid" -gt 1 ] && [ -e "$PROC/$_pid/status" ] || continue    # init, or already gone
        _p="$_pid"
        while [ "$_p" -gt 1 ] && [ "$_p" != "$$" ]; do
            _up=""
            { while read -r _k _v; do [ "$_k" = "PPid:" ] && { _up="$_v"; break; }; done < "$PROC/$_p/status"; } 2>/dev/null
            [ -n "$_up" ] || break
            _p="$_up"
        done
        [ "$_p" = "$$" ] || echo "$_pid"
    done
}

repair_kill_holders() {
    _killed=""
    for _pid in $(repair_holder_pids); do
        _comm=""
        { read -r _comm < "$PROC/$_pid/comm"; } 2>/dev/null
        _killed="$_killed $_pid:$_comm"
        kill -9 "$_pid" 2>/dev/null
    done
    [ -n "$_killed" ] && echo "killed card holders:$_killed"
}

# Unmount the card for fsck, for real. Every mount by its mount point, never by the device:
# BusyBox 1.20's `umount /dev/...` takes only the device's two newest mounts and still reports
# success, so with binds of card files the card itself stays mounted. Never lazily either: a
# detached card is still mounted as far as the kernel is concerned. Holders are killed before
# every try, since a killed process lets go in its own time and a watchdog can respawn a child.
# Returns 0 only when no mount of the card's device is left.
repair_release_card() {
    if [ -z "$CARD_MP" ]; then
        card_is_mounted && return 1
        return 0
    fi
    # As it is mounted now (read-write after tmp_read_only_check), for remount_card.
    _how=$(awk -v mp="$CARD_MP" '$5 == mp { for (i = 7; i <= NF; i++) if ($i == "-") break
        print $(i + 1), $6 "," $(i + 3); exit }' "$MOUNTINFO" 2>/dev/null)
    CARD_FSTYPE="${_how%% *}" CARD_MOUNT_OPTS="${_how#* }"
    _try=0
    while [ "$_try" -lt 10 ]; do
        repair_kill_holders
        sleep 0.2
        card_dependent_mounts | while read -r _mnt; do umount "$_mnt" 2>/dev/null; done
        card_loops | while read -r _l _d; do losetup -d "/dev/$_l" 2>/dev/null; done
        umount "$CARD_MP" 2>/dev/null
        card_is_mounted || return 0
        _try=$((_try + 1))
        echo "the card is still mounted, retrying ($_try)"
        sleep 1
    done
    echo "still mounted after $_try tries:"
    awk -v dev="$SD_DEV" '{ for (i = 7; i <= NF; i++) if ($i == "-") break; if ($(i + 2) == dev) print "  " $5 }' "$MOUNTINFO"
    echo "holders: $(repair_holder_pids | tr '\n' ' ')"
    return 1
}

# Back the way it was, for the log. A bare mount takes the first type the kernel lists, which can
# be msdos: 8.3 names only, so the log would land as SDCARD_R.LOG.
remount_card() {
    _mp="${CARD_MP:-$SD_MOUNTPOINT}"
    [ -n "$CARD_FSTYPE" ] && mount -t "$CARD_FSTYPE" -o "$CARD_MOUNT_OPTS" "$SD_DEV" "$_mp" 2>/dev/null &&
        return 0
    mount "$SD_DEV" "$_mp" 2>/dev/null
}

tmp_read_only_check() {
    echo "Performing read-only check"
    SD_or_sd=$(mount | grep -q sdcard && echo "sdcard" || echo "SDCARD")
    MNT_LINE=$(mount | grep "$SD_or_sd")
    if [ -n "$MNT_LINE" ]; then
        echo "mount line for SD card: $MNT_LINE" -v
        MNT_STATUS=$(echo "$MNT_LINE" | cut -d'(' -f2 | cut -d',' -f1)
        if [ "$MNT_STATUS" = "ro" ] && [ -n "$SD_DEV" ]; then
            echo "SD card is mounted as RO. Attempting to remount."
            mount -o remount,rw "$SD_DEV" "$SD_MOUNTPOINT"
            NEW_MNT_LINE=$(mount | grep "$SD_or_sd")
            echo "new mount line: $NEW_MNT_LINE"
        else
            echo "SD card is not read-only."
        fi
    fi
}

tmp_set_performance() {
    echo "Setting CPU cores 0-3 online; disabling 4-7 if present."
    for cpu in 0 1 2 3; do
        online="/sys/devices/system/cpu/cpu$cpu/online"
        if [ -e "$online" ]; then
            chmod a+w "$online"
            echo 1 > "$online"
            chmod a-w "$online"
        fi
    done
    for cpu in 4 5 6 7; do
        online="/sys/devices/system/cpu/cpu$cpu/online"
        if [ -e "$online" ]; then
            chmod a+w "$online"
            echo 0 > "$online"
            chmod a-w "$online"
        fi
    done
    echo "Locking CPU governor to performance with maximum frequency ${CPU_PERF_MAX_FREQ:-unchanged}"
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo performance >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    [ -n "$CPU_PERF_MAX_FREQ" ] &&
        echo "$CPU_PERF_MAX_FREQ" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
}


  #############################
##### ACTUAL REPAIR PROCESS #####
  #############################

if [ "$1" = "run" ]; then

    mkdir -p "$SDFIX_DIR"     # do this first so the tmp log path is valid
    cd "$SDFIX_DIR"

    {
        resolve_platform_facts
        echo "platform=$PLATFORM device=$SD_DEV mountpoint=$SD_MOUNTPOINT"

        # Strip before staging: spruce's own fsck.fat is on PATH on the Mini and A30. The library
        # path comes in apart (runtimeHelper.sh), and its system folders stay for the tools.
        PATH="$(strip_card_paths "$PATH")"
        LD_LIBRARY_PATH="$(strip_card_paths "${SDFIX_LD_LIBRARY_PATH-$LD_LIBRARY_PATH}")"
        export PATH LD_LIBRARY_PATH
        echo "PATH=$PATH"
        echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

        stage_repair_tools

        tmp_blink
        tmp_hold_off_respawns
        tmp_stop_frontend_service
        tmp_kill_boot_scripts
        tmp_read_only_check
        tmp_set_performance
        rm -f /mnt/SDCARD/FIX_MY_SDCARD

        tmp_display "Attempting to repair SD card. This may take some time." "REPAIRING SD CARD"

        tmp_debug_info    # uncomment to see `ps` and `mount` outputs in your log

        if [ -z "$SD_DEV" ] || [ -z "$FSCK_BIN" ]; then
            echo "Nothing to repair with: SD_DEV='$SD_DEV' FSCK_BIN='$FSCK_BIN'"
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead." \
                "REPAIR FAILED: FIX THE CARD ON A PC"
            sleep 10
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            poweroff
            exit 1
        fi

        if repair_release_card; then
            echo "$SD_DEV unmounted successfully."
        else
            echo "Unable to unmount $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead." \
                "REPAIR FAILED: FIX THE CARD ON A PC"
            sleep 10
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            poweroff
            exit 1
        fi
        
        "$FSCK_BIN" -av "$SD_DEV"
        FSCK_EXIT_CODE=$?
        echo "fsck.fat exited with code $FSCK_EXIT_CODE"
        if [ "$FSCK_EXIT_CODE" -eq 0 ]; then
            echo "fsck.fat has been run on $SD_DEV and reports a clean SD card."

            msg="SD card repair appears to have been successful."
            if [ "$PLATFORM" = "A30" ]; then
                msg="$msg After 10 seconds, your device will shut itself down."
            else
                msg="$msg After 10 seconds, your device will reboot."
            fi
            tmp_display "$msg" "NO ERRORS FOUND: REBOOTING"
            sleep 10
            remount_card
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            [ "$PLATFORM" = "A30" ] && poweroff || reboot

        elif [ "$FSCK_EXIT_CODE" -eq 1 ]; then
            echo "fsck.fat has been run on $SD_DEV and has corrected some filesystem errors."

            msg="SD card repair utility has corrected some filesystem errors. If problems persist after this, please use a PC to repair your card."
            if [ "$PLATFORM" = "A30" ]; then
                msg="$msg After 10 seconds, your device will shut itself down."
            else
                msg="$msg After 10 seconds, your device will reboot."
            fi
            tmp_display "$msg" "SD CARD REPAIRED: REBOOTING"
            sleep 10
            remount_card
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            [ "$PLATFORM" = "A30" ] && poweroff || reboot

        else
            echo "fsck.fat reported errors. Unable to repair $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead." \
                "REPAIR FAILED: FIX THE CARD ON A PC"
            sleep 10
            remount_card
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            poweroff
        fi

    tmp_display_kill
    sync
    poweroff
    while true; do sleep 1 ; done

    } > "$TMP_LOG_PATH" 2>&1
fi