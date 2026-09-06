#!/bin/sh

##### IMPORTS AND CONSTANTS ###################

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"
BG_TREE="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SAVE_IMG="/mnt/SDCARD/spruce/imgs/save.png"

EMU_PROCESSES="ra32.a30 ra32.mini ra32.universal ra64.universal ra64.pixel2 \
ra64.h700 ra32.h700 \
retroarch drastic drastic32 drastic64 pico8_dyn pico8_64 \
flycast flycast2024 yabasanshiro yabasanshiro.trimui dsperate dsperate.a30 \
mupen64plus PPSSPPSDL PPSSPPSDL_TrimUI PPSSPPSDL_$PLATFORM"

STAGE_2_SD_PATH=/mnt/SDCARD/spruce/scripts/save_poweroff_stage2.sh
STAGE_2_TMP_PATH=/tmp/save_poweroff_stage2.sh

# --reboot        reboot instead of powering off
# --usb-storage   the USB Storage Mode app is handing over: no emulator, no
#                 shutdown screen, no syncthing wait, and the mass-storage
#                 gadget is released here, after stage 2 is staged (see
#                 usb_storage_release_gadget)
# --usb-storage-export  the app hands over BEFORE anything is exported: same
#                 skips as --usb-storage, nothing to release here, and stage 2
#                 is told to unmount strictly and then run the export session
#                 from /tmp (usb_session_run) before it reboots
# --repair-sd     the user consented (PyUI asks when the card booted dirty)
#                 to an fsck of the card once it is unmounted; stage 2 runs it
#                 before the power command (SPR-MED-199)
s2_arg=""
USB_STORAGE_EXIT=0
USB_STORAGE_EXPORT=0
SD_REPAIR=0
for arg in "$@"; do
    case "$arg" in
        --reboot) s2_arg="--reboot" ;;
        --usb-storage) USB_STORAGE_EXIT=1 ;;
        --usb-storage-export) USB_STORAGE_EXIT=1; USB_STORAGE_EXPORT=1; s2_arg="--reboot" ;;
        --repair-sd) SD_REPAIR=1 ;;
    esac
done

##### FUNCTION DEFINITIONS ####################

blink_led_if_applicable() {
    [ "$LED_PATH" != "not applicable" ] && echo heartbeat > "$LED_PATH"/trigger
}

# This script's own pid plus every process it is running inside of, up to init.
own_process_chain() {
    local p="$$"
    local chain=""
    while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ]; do
        chain="$chain $p"
        p="$(awk '/^PPid:/ {print $2}' "/proc/$p/status" 2>/dev/null)"
    done
    echo "$chain"
}

kill_current_process() {
    pid="$(pgrep -f '/tmp/cmd_to_run.sh' | head -n1)"
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    # A shutdown can be asked for by the very app we are walking down into: the
    # updater reboots the device from a process the launcher started, so the
    # deepest child of cmd_to_run.sh is this script. Killing it left the device
    # sitting on "Update complete. Rebooting..." with no shutdown running at
    # all, until the user held the power button.
    local protected=" $(own_process_chain) "
    for target in $ppid; do
        case "$protected" in
        *" $target "*)
            log_message "save_poweroff.sh: not killing $target, the shutdown is running inside it"
            continue
            ;;
        esac
        log_message "save_poweroff.sh: killing current process $target"
        kill -9 "$target"
    done
}

unmount_all() {
    sync
    log_message "save_poweroff.sh: Scanning for SD card related mounts..."
    MOUNTS=$(awk '
        {
            target = $5
            split($0, parts, " - ")
            device = parts[2]
            sub(/^[^ ]+ /, "", device)
            sub(/ .*/, "", device)

            # Match by block device, mount point under SD, source file on SD,
            # or overlay options referencing SD paths
            if (device == "'"$SD_DEV"'" ||
                target ~ "^'"$SD_MOUNTPOINT"'(/|$)" ||
                device ~ "^'"$SD_MOUNTPOINT"'/" ||
                device ~ "^/mnt/SDCARD/" ||
                ($0 ~ "/mnt/SDCARD" && device == "overlay")) {
                print target
            }
        }
    ' /proc/self/mountinfo)

    # Unmount deepest paths first, but skip the main SD mount (stage2 handles that)
    echo "$MOUNTS" | sort -r | while read -r TARGET; do
        [ -z "$TARGET" ] && continue
        if [ "$TARGET" != "$SD_MOUNTPOINT" ]; then
            log_message "save_poweroff.sh: Attempting to unmount $TARGET"
            umount "$TARGET" 2>/dev/null || umount -l "$TARGET" 2>/dev/null || \
                log_message "save_poweroff.sh: Failed to unmount $TARGET"
        fi
    done
}

attempt_to_close_emu_gracefully() {
    if pgrep -f "PPSSPPSDL" >/dev/null; then
        close_gracefully_ppsspp
    elif pgrep -f "drastic32" >/dev/null; then
        close_gracefully_drastic_steward
    else
        close_gracefully_all_emus
    fi
}

close_gracefully_ppsspp() {
    {
        # send autosave hot key
        echo 1 314 1 # SELECT down
        echo 1 311 1 # R1 down
        echo 1 311 0 # R1 up
        echo 1 314 0 # SELECT up
        echo 0 0 0   # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_RA_AND_PPSSPP || \
    log_message "Warning: sendevent failed during PPSSPP autosave"
    sleep 1
    killall -q -15 PPSSPPSDL_TrimUI 2>/dev/null
    killall -q -15 PPSSPPSDL_$PLATFORM 2>/dev/null
}

close_gracefully_drastic_steward() {
    {
        echo $B_L3 1    # Fn1 press
        echo $B_L3 0    # Fn1 release
        sleep 0.1
        echo $B_MENU 1  # MENU press
        echo $B_L1 1    # L1 press
        echo $B_L1 0    # L1 release
        echo $B_MENU 0  # MENU release
        sleep 0.1
        echo $B_MENU 1  # MENU press
        echo $B_L1 1    # L1 press
        echo $B_L1 0    # L1 release
        echo $B_MENU 0  # MENU release
        echo 0 0 0      # tell sendevent to exit
    } | sendevent $EVENT_PATH_SEND_TO_DRASTIC || \
    log_message "Warning: sendevent failed during DraStic-Steward autosave"
    sleep 1
    killall -q -15 drastic32 2>/dev/null
}

close_gracefully_all_emus() {
    for process in $EMU_PROCESSES; do
        killall -q -15 "$process" 2>/dev/null
    done
}

wait_for_graceful_emu_exit() {
    MAX_LOOPS=200   # ~10 seconds at 0.05s
    COUNT=0
    while :; do
        for process in $EMU_PROCESSES; do
            if killall -q -0 "$process" 2>/dev/null; then
                sleep 0.05
                COUNT=$((COUNT + 1))
                [ "$COUNT" -ge "$MAX_LOOPS" ] && break 2
                continue 2
            fi
        done
        break
    done
}

close_forcefully_all_emus() {
    for process in $EMU_PROCESSES; do
        killall -q -0 "$process" 2>/dev/null && killall -q -9 "$process" 2>/dev/null
    done
}

close_non_emu_cmd_to_run() {
    [ -f /tmp/cmd_to_run.sh ] || return 1
    if cat /tmp/cmd_to_run.sh | grep -q -v -e '/mnt/SDCARD/Emu' -e '/media/sdcard0/Emu' -e '/mnt/SDCARD/Emus'; then
        kill_current_process
        # remove lastgame flag to prevent loading any App after next boot
        rm -f -- "${FLAGS_DIR}/lastgame.lock"
    fi
}

stop_problematic_scripts() {
    # kill principal and runtime first so no new app / MainUI will be loaded anymore
    killall -q -15 runtime.sh
    killall -q -15 principal.sh

    # Ensure PyUI message writer can run
    killall -q -9 MainUI
    sleep 0.5

    # kill lid watchdog so that closing the lid doesn't interrupt the save/shutdown procedure
    pgrep -f "lid_watchdog_v2.sh" | xargs -r kill

    # kill enforceSmartCPU first so no CPU setting is changed during shutdown
    killall -q -15 enforceSmartCPU.sh

    # explicitly kill other watchdogs, etc. that might be keeping the SD card from unmounting.
    killall -q -9 homebutton_watchdog.sh
    killall -q -9 buttons_watchdog.sh
    killall -q -9 idlemon_mm.sh
    killall -q -9 low_power_warning.sh
    killall -q -9 theme_watchdog.sh
    killall -q -9 volume_sync_watchdog.sh
    killall -q -9 inotifywait
    killall -q -9 inotifywatch
    killall -q -9 getevent
    killall -q -9 sendevent
}

display_appropriate_icon_and_message() {
    if flag_check "forced_shutdown"; then
        start_pyui_message_writer
        display_image_and_text "$SAVE_IMG" 33 10 "Battery level is below 1%. Shutting down to prevent progress loss." 60 50
        flag_remove "forced_shutdown"
        sleep 1.5 # Let user read message
    elif ! flag_check "in_menu"; then
        start_pyui_message_writer
        display_image_and_text "$SAVE_IMG" 33 10 "Saving and shutting down... Please wait a moment." 60 50
        sleep 1.5 # Let user read message
    fi
}

dim_screen_and_do_syncthing_check() {
    syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"
    if [ "$syncthing_enabled" = "True" ] && flag_check "emulator_launched"; then
        log_message "Syncthing is enabled, WiFi connection needed"

        if check_and_connect_wifi; then
            start_syncthing_process
            # Dimming screen before syncthing sync check
            dim_screen &
            DIM_SCREEN_PID=$!
            /mnt/SDCARD/spruce/scripts/syncthing_sync_check.sh --shutdown
        fi

        flag_remove "syncthing_startup_synced"
    else
        dim_screen &
        DIM_SCREEN_PID=$!
    fi
}

kill_remaining_background_processes() {
    # Stop the PyUI message writer — it has file handles open on the SD card
    stop_pyui_message_writer

    # Kill dim_screen if it's still running (writes to sysfs, but inherits SD fds)
    if [ -n "$DIM_SCREEN_PID" ]; then
        kill "$DIM_SCREEN_PID" 2>/dev/null
        wait "$DIM_SCREEN_PID" 2>/dev/null
    fi

    # Kill syncthing if still alive — it actively writes to SD card
    killall -q -9 syncthing 2>/dev/null
    killall -q -9 wpa_supplicant 2>/dev/null

    # Brief pause for file descriptor cleanup
    sleep 0.2
}

clean_up_flags() {
    # Set flag to trigger autoresume on boot if appropriate. USB Storage Mode
    # counts as the menu: there is nothing to resume into.
    if flag_check "in_menu" || usb_storage_exit; then
        flag_remove "save_active"
        log_message "save_active cleared by save_poweroff: shutdown initiated from menu"
    else
        flag_add "save_active"
        log_message "save_active set by save_poweroff: shutdown initiated outside menu"
    fi
    flag_remove "sleep.powerdown"
    flag_remove "emulator_launched"
    flag_remove "setting_cpu" # in case one of the set_cpu_mode() functions got interrupted
}

# Stage 2 must be copied off the card BEFORE anything is unmounted. On the
# Miniloong the card is at /mnt/sdcard and /mnt/SDCARD is a separate BIND mount
# (the Flip's /mnt/SDCARD is a symlink), so unmount_all - which spares only
# $SD_MOUNTPOINT - takes /mnt/SDCARD away and the copy below found nothing:
# stage 2 never ran there, the fallback ran the power-off command for a
# reboot too, and three shutdown attempts left the device on its unmounted
# card (SPR-HIGH-051, 2026-08-28 and 2026-09-04). Called right after the
# starting breadcrumb, while every path is still mounted.
SD_REPAIR_STAGED=0
stage_shutdown_stage_2() {
    if [ -e "$STAGE_2_SD_PATH" ]; then
        if cp "$STAGE_2_SD_PATH" "$STAGE_2_TMP_PATH" 2>/dev/null; then
            chmod +x "$STAGE_2_TMP_PATH"
            log_message "save_poweroff.sh: staged stage 2 at $STAGE_2_TMP_PATH"
        else
            log_message "save_poweroff.sh: WARNING could not stage stage 2 to /tmp"
        fi
    else
        log_message "save_poweroff.sh: WARNING stage 2 script missing at $STAGE_2_SD_PATH"
    fi
    # The user consented to a repair (PyUI asked because the card booted dirty):
    # stage fsck.fat and the platform facts with stage 2, which runs it once the
    # card is unmounted (SPR-MED-199). Only on request - it costs a megabyte of
    # /tmp and a card read.
    if [ "$SD_REPAIR" = "1" ] && [ -f /mnt/SDCARD/spruce/scripts/shutdown_ui.sh ]; then
        . /mnt/SDCARD/spruce/scripts/shutdown_ui.sh
        if shutdown_ui_stage; then
            SD_REPAIR_STAGED=1
            log_message "save_poweroff.sh: repair consented, stage 2 will fsck the card"
        else
            log_message "save_poweroff.sh: WARNING could not stage the repair, card left as it is"
        fi
    fi
}

usb_storage_exit() {
    [ "$USB_STORAGE_EXIT" = "1" ]
}

# Release the USB mass-storage gadget on behalf of App/USBStorageMode.
#
# Closing the LUN closes the card's block device, and on TrimUI stock udev's
# block `watch` rule turns that close into a synthesized `change` uevent that
# /sbin/mdev answers with /etc/mdev/sdcard_remove: `umount -l` of the card,
# `rm -rf` of its mount point, `rm -f /mnt/SDCARD` (SPR-HIGH-053, measured on
# the Smart Pro S). From that instant nothing on the card can be reached by
# path. So this runs only after stage 2 is staged into /tmp and every helper
# that needs the card has had its turn; what follows it (unmount_all, the
# stage-2 hand-off) works from memory and /tmp.
usb_storage_release_gadget() {
    hook=/mnt/SDCARD/App/USBStorageMode/usb_gadget.sh
    if [ ! -f "$hook" ]; then
        log_message "save_poweroff.sh: WARNING usb gadget hook missing at $hook"
        return 1
    fi
    . "$hook"
    if ! usb_gadget_platform_setup; then
        log_message "save_poweroff.sh: WARNING no USB gadget table for $PLATFORM"
        return 1
    fi
    log_message "save_poweroff.sh: releasing the USB mass-storage gadget ($PLATFORM)"
    usb_gadget_release
    log_message "save_poweroff.sh: USB gadget released"
}

exec_shutdown_stage_2() {
    log_message "Running stage 2 of save_poweroff from /tmp."
    sync
    # Prefer the copy staged before the unmounts; fall back to copying now.
    if [ ! -x "$STAGE_2_TMP_PATH" ] && [ -e "$STAGE_2_SD_PATH" ]; then
        cp "$STAGE_2_SD_PATH" "$STAGE_2_TMP_PATH" 2>/dev/null && chmod +x "$STAGE_2_TMP_PATH"
    fi
    if [ -x "$STAGE_2_TMP_PATH" ]; then
        # Reset environment BEFORE exec so the new shell interpreter
        # doesn't load shared libraries from the SD card
        export PATH=/usr/bin:/usr/sbin:/bin:/sbin
        unset LD_LIBRARY_PATH
        # Stage 2 runs from /tmp with the card gone, so it cannot source the
        # device layer to ask this itself. Answer it here, while we still can,
        # and hand the answer over in the environment.
        if device_needs_strict_unmount; then
            export SPRUCE_STRICT_UNMOUNT=1
        else
            export SPRUCE_STRICT_UNMOUNT=0
        fi
        if device_power_transition_bypasses_init; then
            export SPRUCE_FORCE_POWER_TRANSITION=1
        else
            export SPRUCE_FORCE_POWER_TRANSITION=0
        fi
        # The export session needs a card that is really gone, so the strict
        # unmount is forced regardless of the platform default.
        if [ "$USB_STORAGE_EXPORT" = "1" ]; then
            export SPRUCE_STRICT_UNMOUNT=1
            export SPRUCE_USB_EXPORT=1
        else
            export SPRUCE_USB_EXPORT=0
        fi
        # A consented repair needs the card really off: the single umount of
        # the original path fails on any lingering holder (an orphaned
        # getevent did it on the Smart Pro S), stage 2 then refuses to fsck a
        # lazily detached card, and the question comes back next boot. The
        # strict path retries with a sweep between attempts.
        if [ "$SD_REPAIR_STAGED" = "1" ]; then
            export SPRUCE_STRICT_UNMOUNT=1
        fi
        export SPRUCE_SD_REPAIR="$SD_REPAIR_STAGED"
        exec "$STAGE_2_TMP_PATH" "$s2_arg"
    else
        # No stage 2 at all: still honour what was asked for.
        if [ "$s2_arg" = "--reboot" ]; then
            log_message "ERROR: Stage 2 script missing! Executing device_run_reboot_cmd() instead."
            device_run_reboot_cmd
        else
            log_message "ERROR: Stage 2 script missing! Executing run_poweroff_cmd() instead."
            run_poweroff_cmd
        fi
    fi
}

    #######################################
##### PREVENT RE-ENTRY IF ALREADY RUNNING #####
    #######################################

LOCKDIR="/tmp/save_poweroff.lock"
PIDFILE="$LOCKDIR/pid"
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    oldpid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        log_message "save_poweroff.sh called in duplicate. Ignoring second call."
        exit 0
    fi
    log_message "save_poweroff.sh reclaiming stale lock (owner ${oldpid:-unknown} gone)."
fi
echo $$ > "$PIDFILE"
trap '[ "$(cat "$PIDFILE" 2>/dev/null)" = "$$" ] && rm -rf "$LOCKDIR"' EXIT INT TERM



                  ########
################### MAIN ######################
                  ########

# BaseOS runs the frontend session from an inittab respawn entry, so killing
# runtime.sh below only makes init start another one - and that fresh session
# races this shutdown. It is not merely noise: its read_only_check sees the card
# we just remounted read-only and runs `mount -o remount,rw` to "repair" it,
# undoing the clean unmount seconds before the power command. Observed exactly
# that - the respawned session logged two lines, went silent as the card went
# read-only, and the next boot still reported a dirty filesystem.
#
# Raise a flag runtime.sh checks on startup so the respawned session exits at
# once. It lives in /tmp, so a real boot never sees it.
#
# Only where the strict path applies. Nothing else in the fleet respawns its
# frontend from init, so the flag would never be read there - and a flag that is
# never read is still a flag that can be left behind by an aborted shutdown and
# make the next runtime.sh exit for no reason.
if device_needs_strict_unmount; then
    flag_add "shutting_down" --tmp
fi

# Breadcrumbs. Without them a hang anywhere in the shutdown path is
# indistinguishable from the script never having run at all - the log simply
# stops, which is exactly how the RGB30 lockup first presented. These are three
# writes on a path that ends in a poweroff; they cost nothing.
log_message "save_poweroff.sh: starting (arg=${1:-none}, platform=$PLATFORM)"
stage_shutdown_stage_2

blink_led_if_applicable
device_prepare_for_poweroff
log_message "save_poweroff.sh: device prepared, closing apps"
log_activity_event "$(get_current_app)" "STOP"
stop_problematic_scripts

if ! usb_storage_exit && ! flag_check "in_menu"; then
    attempt_to_close_emu_gracefully
    wait_for_graceful_emu_exit
    sync
    close_forcefully_all_emus
    close_non_emu_cmd_to_run
fi

if usb_storage_exit; then
    # The app is what cmd_to_run.sh launched, so principal.sh recorded it as
    # the last game. It is not resumable: a boot that auto-resumed into USB
    # Storage Mode sat in the app with no network services up (measured on
    # the TSPS, 2026-09-05). Drop the lastgame record now, the way a
    # non-emulator command is dropped, and let clean_up_flags treat this as a
    # shutdown from the menu so save_active is cleared rather than set.
    close_non_emu_cmd_to_run
    rm -f -- "${FLAGS_DIR}/lastgame.lock"
else
    display_appropriate_icon_and_message
    dim_screen_and_do_syncthing_check
fi
clean_up_flags
alsactl store 2>/dev/null
kill_remaining_background_processes

# Systemd handles graceful shutdown on the pixel2
# Reboot-only preparation while the device functions are still reachable
# (stage 2 runs from /tmp with the card gone). See device_prepare_for_reboot.
if [ "$s2_arg" = "--reboot" ]; then
    device_prepare_for_reboot
fi

# USB Storage Mode: the gadget goes last among the things that need the card,
# and before any power command - the card may vanish the moment it is released.
if usb_storage_exit && [ "$USB_STORAGE_EXPORT" != "1" ]; then
    usb_storage_release_gadget
fi

# The export session must reach stage 2 even where the system would handle
# the unmount at a real power-off; the app only takes this path where spruce
# owns the card, this is the second line of defence.
if [ "$USB_STORAGE_EXPORT" != "1" ] && device_system_handles_sdcard_unmount; then

    if [ "$s2_arg" = "--reboot" ]; then
        device_run_reboot_cmd
    else
        run_poweroff_cmd
    fi

    exit 0
fi

unmount_all
sleep 0.1
unmount_all

exec_shutdown_stage_2
