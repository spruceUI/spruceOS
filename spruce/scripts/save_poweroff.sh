#!/bin/sh

##### IMPORTS AND CONSTANTS ###################

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

FLAGS_DIR="/mnt/SDCARD/spruce/flags"
BG_TREE="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
SAVE_IMG="/mnt/SDCARD/spruce/imgs/save.png"

EMU_PROCESSES="ra64.miyoo ra32.miyoo retroarch
retroarch.$PLATFORM retroarch.trimui ra64.trimui_$PLATFORM \
drastic drastic32 drastic64 pico8_dyn pico8_64 \
flycast flycast-stock yabasanshiro yabasanshiro.trimui \
mupen64plus PPSSPPSDL PPSSPPSDL_TrimUI PPSSPPSDL_$PLATFORM"

STAGE_2_SD_PATH=/mnt/SDCARD/spruce/scripts/save_poweroff_stage2.sh
STAGE_2_TMP_PATH=/tmp/save_poweroff_stage2.sh

if [ "$1" = "--reboot" ]; then
    s2_arg="--reboot";
else
    s2_arg=""
fi

##### FUNCTION DEFINITIONS ####################

blink_led_if_applicable() {
    [ "$LED_PATH" != "not applicable" ] && echo heartbeat > "$LED_PATH"/trigger
}

kill_current_process() {
    pid="$(pgrep -f '/tmp/cmd_to_run.sh' | head -n1)"
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    if [ "" != "$ppid" ]; then
        kill -9 $ppid
    fi
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
        rm "${FLAGS_DIR}/lastgame.lock"
    fi
}

stop_problematic_scripts() {
    # kill principal and runtime first so no new app / MainUI will be loaded anymore
    killall -q -15 runtime.sh
    killall -q -15 principal.sh

    # Ensure legacy display can run
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
    killall -q -9 autoIconRefresh.sh
    killall -q -9 inotifywait
    killall -q -9 inotifywatch
    killall -q -9 getevent
    killall -q -9 sendevent
}

display_appropriate_icon_and_message() {
    if flag_check "in_menu"; then
        display --icon "$BG_TREE" -t "Shutting down..."
    elif flag_check "forced_shutdown"; then
        display --icon "$SAVE_IMG" -t "Battery level is below 1%. Shutting down to prevent progress loss."
        flag_remove "forced_shutdown"
    else
        display --icon "$SAVE_IMG" -t "Saving and shutting down... Please wait a moment."
    fi
    sleep 1 # Let user read any messages
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
    # Stop legacy display — it has file handles open on the SD card
    display_kill

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
    # Set flag to trigger autoresume on boot if appropriate
    if flag_check "in_menu"; then
        flag_remove "save_active"
    else
        flag_add "save_active"
    fi
    flag_remove "sleep.powerdown"
    flag_remove "emulator_launched"
    flag_remove "setting_cpu" # in case one of the set_cpu_mode() functions got interrupted
}

exec_shutdown_stage_2() {
    log_message "Running stage 2 of save_poweroff from /tmp."
    sync
    if [ -e "$STAGE_2_SD_PATH" ]; then
        cp $STAGE_2_SD_PATH $STAGE_2_TMP_PATH
        chmod +x $STAGE_2_TMP_PATH
        # Reset environment BEFORE exec so the new shell interpreter
        # doesn't load shared libraries from the SD card
        export PATH=/usr/bin:/usr/sbin:/bin:/sbin
        unset LD_LIBRARY_PATH
        exec "$STAGE_2_TMP_PATH" "$s2_arg"
    else
        log_message "ERROR: Stage 2 script missing! Executing run_poweroff_cmd() instead."
        run_poweroff_cmd
    fi
}

    #######################################
##### PREVENT RE-ENTRY IF ALREADY RUNNING #####
    #######################################

PIDFILE="/tmp/save_poweroff.pid"
if [ -f "$PIDFILE" ]; then
    oldpid="$(cat "$PIDFILE")"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    log_message "save_poweroff.sh called in duplicate. Ignoring second call."
        exit 0
    fi
fi
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT INT TERM



                  ########
################### MAIN ######################
                  ########

blink_led_if_applicable
device_prepare_for_poweroff
log_activity_event "$(get_current_app)" "STOP"
stop_problematic_scripts

if ! flag_check "in_menu"; then
    attempt_to_close_emu_gracefully
    wait_for_graceful_emu_exit
    sync
    close_forcefully_all_emus
    close_non_emu_cmd_to_run
fi

display_appropriate_icon_and_message
dim_screen_and_do_syncthing_check
clean_up_flags

# Systemd handles graceful shutdown on the pixel2
if device_system_handles_sdcard_unmount; then
    kill_remaining_background_processes
    if [ "$s2_arg" = "--reboot" ]; then
        device_run_reboot_cmd
    else
        run_poweroff_cmd
    fi

    exit 0
fi

alsactl store

kill_remaining_background_processes

unmount_all
sleep 0.1
unmount_all

exec_shutdown_stage_2
