#!/bin/sh

# mnt "/mnt/SDCARD/spruce/scripts/whte_rbt.obj"
# >access security
# access: PERMISSION DENIED.
# >access security grid
# access: PERMISSION DENIED.
# >access main security grid
# access: PERMISSION DENIED.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/runtimeHelper.sh
. /mnt/SDCARD/spruce/scripts/trace.sh
SYSTEM_EMIT="${SYSTEM_EMIT:-/mnt/SDCARD/spruce/scripts/system-emit}"

UNPACK_STATE_FILE="/mnt/SDCARD/Saves/spruce/unpacker_state"

read_unpack_state() {
    if [ -f "$UNPACK_STATE_FILE" ]; then
        sed -n 's/^state=//p' "$UNPACK_STATE_FILE" | head -n 1
    else
        echo "idle"
    fi
}

[ "$LED_PATH" != "not applicable" ] && echo mmc0 > "$LED_PATH"/trigger

export HOME="/mnt/SDCARD"

rotate_logs
log_file="/mnt/SDCARD/Saves/spruce/spruce.log" # Resetting log file location
log_message "---------Starting up---------"
trace_fsm_boot_init "runtime.sh" || true
emit_startup_av_trace_from_config || true

run_sd_card_fix_if_triggered    # do this before anything else
set_performance
device_init
set_volume_to_config &
# Check if WiFi is enabled and bring up network services if so
enable_or_disable_wifi_per_system_json &

# Flag cleanup
flag_remove "log_verbose" &
flag_remove "low_battery" &
flag_remove "in_menu" &

unstage_archives_wanted
check_and_handle_firmware_app &
check_and_hide_update_app &

# Check for first_boot flags and run Unpacker accordingly
if flag_check "first_boot_${PLATFORM}"; then
    "$SYSTEM_EMIT" process archiveUnpacker "FIRSTBOOT_SILENT_LAUNCH" "runtime.sh" "platform=$PLATFORM" || true
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent &
    "$SYSTEM_EMIT" process archiveUnpacker "SILENT_LAUNCH_PID" "runtime.sh" "pid=$!" || true
    log_message "Unpacker started silently in background due to first_boot flag"
    "$SYSTEM_EMIT" process firstboot "ENTER_FIRSTBOOT_SCRIPT" "runtime.sh" "silent unpacker may still be active" || true
    "/mnt/SDCARD/spruce/scripts/firstboot.sh"
    "$SYSTEM_EMIT" process firstboot "EXIT_FIRSTBOOT_SCRIPT" "runtime.sh" "returned from firstboot.sh" || true
else
    "$SYSTEM_EMIT" process archiveUnpacker "FOREGROUND_LAUNCH" "runtime.sh" "non-first_boot path" || true
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
    unpack_state="$(read_unpack_state)"
    if [ "$unpack_state" = "running" ]; then
        log_message "Unpacker: foreground phases returned with background worker still active."
    else
        log_message "Unpacker: foreground run returned with state=$unpack_state."
    fi
    "$SYSTEM_EMIT" process archiveUnpacker "FOREGROUND_RESULT" "runtime.sh" "state=$unpack_state" || true
fi

/mnt/SDCARD/spruce/scripts/set_up_swap.sh &

launch_startup_watchdogs
"$SYSTEM_EMIT" process runtime "STARTUP_WATCHDOGS_LAUNCHED" "runtime.sh" "startup_watchdogs launched" || true

# check whether to auto-resume into a game
auto_resume_staged=0
if flag_check "save_active"; then
    if auto_resume_game; then
        auto_resume_staged=1
        log_message "Auto Resume contract: staged intent in runtime helper; principal.sh owns execution."
    else
        log_message "Auto Resume contract: staging failed; continuing with normal runtime/menu path."
    fi
else
    log_message "Auto Resume skipped (no save_active flag)"
fi

/mnt/SDCARD/spruce/scripts/autoIconRefresh.sh &
developer_mode_task &
update_checker &
# update_notification

# Initialize CPU settings
set_smart

# Set up the boot_to action prior to getting into the principal loop
set_up_boot_action

if flag_check "save_active"; then
    if [ "$auto_resume_staged" -eq 1 ]; then
        log_message "save_active cleared by runtime after successful stage handoff to principal.sh"
    else
        log_message "save_active cleared by runtime without stage handoff (fallback path)"
    fi
fi
flag_remove "save_active"

# start main loop
log_message "Starting main loop"
/mnt/SDCARD/spruce/scripts/principal.sh
