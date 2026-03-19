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

run_unpacker_foreground() {
    launch_event="$1"
    launch_context="$2"
    result_event="$3"
    log_prefix="$4"
    allow_background_state="$5"
    force_foreground_precmd="$6"

    "$SYSTEM_EMIT" process archiveUnpacker "$launch_event" "runtime.sh" "$launch_context" || true
    if [ "$force_foreground_precmd" = "1" ]; then
        UNPACKER_FORCE_FOREGROUND_PRECMD=1 /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
    else
        /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
    fi

    unpack_state="$(read_unpack_state)"
    if [ "$allow_background_state" = "1" ] && [ "$unpack_state" = "running" ]; then
        log_message "Unpacker: $log_prefix returned with background worker still active."
    else
        log_message "Unpacker: $log_prefix returned with state=$unpack_state."
    fi
    "$SYSTEM_EMIT" process archiveUnpacker "$result_event" "runtime.sh" "state=$unpack_state" || true
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

# Check for first_boot flags and run extraction in a deterministic sequence.
# firstboot handles package extraction (PortMaster/ScummVM), then archiveUnpacker
# runs in foreground for themes/preMenu/preCmd so extraction paths do not overlap.
if flag_check "first_boot_${PLATFORM}"; then
    "$SYSTEM_EMIT" process firstboot "ENTER_FIRSTBOOT_SCRIPT" "runtime.sh" "sequential extraction phase: packages" || true
    "/mnt/SDCARD/spruce/scripts/firstboot.sh"
    "$SYSTEM_EMIT" process firstboot "EXIT_FIRSTBOOT_SCRIPT" "runtime.sh" "returned from firstboot.sh" || true

    start_pyui_message_writer
    display_image_and_text "/mnt/SDCARD/spruce/imgs/refreshing.png" 35 25 "Unpacking themes.........." 75
    sleep 5
    run_unpacker_foreground \
        "FIRSTBOOT_FOREGROUND_LAUNCH" \
        "sequential extraction after firstboot" \
        "FIRSTBOOT_FOREGROUND_RESULT" \
        "firstboot foreground run" \
        "0" \
        "1"
    display_image_and_text "/mnt/SDCARD/spruce/imgs/smile.png" 35 25 "Happy gaming.........." 75
    sleep 5
else
    run_unpacker_foreground \
        "FOREGROUND_LAUNCH" \
        "non-first_boot path" \
        "FOREGROUND_RESULT" \
        "foreground run" \
        "1" \
        "0"
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
