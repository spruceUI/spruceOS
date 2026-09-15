#!/bin/sh

# TODO: opt out with a tmp_confirm() ?

EXPERT_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/expertappswitch.png"
TMP_LOG_PATH=/tmp/SDCARD_REPAIR.log
FINAL_LOG_PATH="/mnt/SDCARD/SDCARD_REPAIR.log"
FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"
SDFIX_DIR=/tmp/sdfix


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



  #################################
##### ABRIDGED HELPER FUNCTIONS #####
  #################################

# Platform facts. runtimeHelper.sh sources helperFunctions.sh and the platform
# cfg before running us, and exports all of this, so inherit it. Run by hand
# there is no such environment, so source it off the card - which is still
# mounted at this point. Either way the cfg stays the single source of truth;
# this script used to keep a second copy as a cpuinfo table, and every device
# added since was missing from it.
resolve_platform_facts() {
    if [ -z "$PLATFORM" ] || [ -z "$SD_MOUNTPOINT" ]; then
        . /mnt/SDCARD/spruce/scripts/helperFunctions.sh
    fi

    SD_MOUNTPOINT="${SD_MOUNTPOINT:-/mnt/SDCARD}"

    # Ask the kernel which device is mounted there and prefer its answer to the
    # cfg's, because the node is not fixed: dArkMoss finds the card by label so
    # its number follows probe order, and BaseOS mounts TF2 if it is there and
    # TF1's own FAT partition (mmcblk0p7) if it is not - while the XX cfg names
    # mmcblk1p1 either way. Unmounting a device other than the one mounted here
    # just fails, and a failed unmount is the whole bug this script keeps hitting.
    # /mnt/SDCARD is a symlink to /mnt/sdcard on BaseOS, so match on the real path.
    _mount_path=$(readlink -f "$SD_MOUNTPOINT" 2>/dev/null)
    [ -n "$_mount_path" ] || _mount_path="$SD_MOUNTPOINT"
    _mounted_dev=$(awk -v mp="$_mount_path" '$2==mp {print $1; exit}' /proc/mounts 2>/dev/null)
    if [ -n "$_mounted_dev" ]; then
        SD_DEV="$_mounted_dev"
    fi

    DISPLAY_WIDTH="${DISPLAY_WIDTH:-640}"
    DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-480}"
    DISPLAY_ROTATION="${DISPLAY_ROTATION:-0}"

    # Platforms that cannot run display_text.elf set this to "not applicable".
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

# Drop card entries from a colon-separated path list. Once the card is
# unmounted anything resolved through them is gone - and that includes mount,
# sync and poweroff on the platforms whose PATH leads with the card.
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

# Copy everything the repair needs off the card before it goes away: the
# display tool and its assets, and fsck.fat unless the base system has its own
# (dArkMoss is Debian and ships one, which outlives the unmount for free).
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

# Best effort. The Miyoo Mini stubs display() out entirely and the RGB30's
# display_text.elf dies at SDL_CreateWindow on its Mali blob, so a device that
# cannot draw still gets its card repaired - silently, with the log to say so.
tmp_display() {
    tmp_display_kill

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

# dArkMoss runs spruce from spruce-launch.service, which has Restart=on-failure
# and an ExecStartPre that mounts the card. Killing runtime.sh below ends that
# unit's main process, so without stopping it first systemd remounts the card
# three seconds into the fsck. KillMode=process means stopping the unit does not
# take this script with it.
tmp_stop_frontend_service() {
    command -v systemctl >/dev/null 2>&1 || return 0
    if systemctl stop spruce-launch.service 2>/dev/null; then
        echo "Stopped spruce-launch.service so it cannot remount the card."
    fi
}

# The list save_poweroff.sh kills before it unmounts, for the same reason: any
# of these still running holds files open on the card and umount refuses.
# runtime.sh and principal.sh go first so nothing launches a new app behind us.
tmp_kill_boot_scripts() {
    echo "Attempting to kill any boot scripts."
    for script in runtime.sh principal.sh MainUI main tee runmiyoo.sh runtrimui.sh \
        runmagicx.sh updater homebutton_watchdog.sh buttons_watchdog.sh idlemon \
        idlemon_mm.sh low_power_warning.sh theme_watchdog.sh volume_sync_watchdog.sh \
        inotifywait inotifywatch getevent sendevent ; do
        if killall -9 "$script" ; then
            echo "Killed ${script}."
        fi
        sleep 0.1
    done
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

        # Drop the card from the search paths BEFORE staging: spruce ships its
        # own fsck.fat in spruce/bin, which is on PATH on the Mini and the A30,
        # so command -v would otherwise settle on the copy that is about to be
        # unmounted.
        #
        # This also means the message below cannot link against SDL on the card,
        # so devices whose SDL lives there (RGB30, Miniloong, the XX line) repair
        # without on-screen text. That is the trade on purpose: a display process
        # holding libraries open on the card is itself a reason umount refuses,
        # and a silent repair beats a pretty message and a failed unmount.
        PATH="$(strip_card_paths "$PATH")"
        LD_LIBRARY_PATH="$(strip_card_paths "$LD_LIBRARY_PATH")"
        export PATH LD_LIBRARY_PATH
        echo "PATH=$PATH"
        echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

        stage_repair_tools

        tmp_blink
        tmp_stop_frontend_service
        tmp_kill_boot_scripts
        tmp_read_only_check
        tmp_set_performance
        # The literal path the setting-up phase writes and runtimeHelper checks,
        # not $SD_MOUNTPOINT: clearing a different path would boot straight back
        # into the repair.
        rm -f /mnt/SDCARD/FIX_MY_SDCARD

        tmp_display "Attempting to repair SD card. This may take some time."

        tmp_debug_info    # uncomment to see `ps` and `mount` outputs in your log

        if [ -z "$SD_DEV" ] || [ -z "$FSCK_BIN" ]; then
            echo "Nothing to repair with: SD_DEV='$SD_DEV' FSCK_BIN='$FSCK_BIN'"
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
            sleep 10
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            poweroff
            exit 1
        fi

        # Retry rather than give up on the first refusal. systemctl stop returns
        # before the unit's children are actually gone (it is KillMode=process),
        # and a watchdog on its way out can hold the card for a moment longer.
        # Something that never lets go still ends in the failure branch below.
        _umounted=0
        _tries=0
        while [ "$_tries" -lt 10 ]; do
            if umount "$SD_DEV"; then
                _umounted=1
                break
            fi
            _tries=$((_tries + 1))
            echo "umount refused, waiting for holders to exit ($_tries)"
            sleep 1
        done

        if [ "$_umounted" -eq 1 ]; then
            echo "$SD_DEV unmounted successfully."
        else
            echo "Unable to unmount $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
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
            tmp_display "$msg"
            sleep 10
            mount "$SD_DEV" "$SD_MOUNTPOINT" 2>/dev/null
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
            tmp_display "$msg"
            sleep 10
            mount "$SD_DEV" "$SD_MOUNTPOINT" 2>/dev/null
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            [ "$PLATFORM" = "A30" ] && poweroff || reboot

        else
            echo "fsck.fat reported errors. Unable to repair $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
            sleep 10
            mount "$SD_DEV" "$SD_MOUNTPOINT" 2>/dev/null
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