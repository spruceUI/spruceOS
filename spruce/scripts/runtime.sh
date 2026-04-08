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

WIKI_ICON="/mnt/SDCARD/spruce/imgs/book.png"
HAPPY_ICON="/mnt/SDCARD/spruce/imgs/smile.png"
SPRUCE_ICON="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"

initialize_system_emit_gate
if system_emit_gate_enabled; then
    . /mnt/SDCARD/spruce/scripts/trace.sh
fi

[ "$LED_PATH" != "not applicable" ] && echo mmc0 > "$LED_PATH"/trigger

export HOME="/mnt/SDCARD"

rotate_logs
log_file="/mnt/SDCARD/Saves/spruce/spruce.log" # Resetting log file location
log_message "---------Starting up---------"
if system_emit_gate_enabled; then
    trace_fsm_boot_init "runtime.sh" || true
    emit_startup_av_trace_from_config || true
fi

run_sd_card_fix_if_triggered    # do this before anything else
set_performance
device_init
{ sleep 1.5; set_volume_to_config; } &
# Check if WiFi is enabled and bring up network services if so
enable_or_disable_wifi_per_system_json &

# Flag cleanup
flag_remove "log_verbose" &
flag_remove "low_battery" &
flag_remove "in_menu" &

unstage_archives_wanted
check_and_handle_firmware_app &
check_and_hide_update_app &

# firstboot.sh owns onboarding and firstboot-required phases, but runtime owns the single
# closing UX because only runtime knows when every required foreground unpack step has
# finished. firstboot may return success, warning, or failure; runtime chooses the closing
# UX accordingly. "Happy gaming" should remain first-boot-only and appear once.
if flag_check "first_boot_${PLATFORM}"; then
    "$SYSTEM_EMIT" process runtime "FIRSTBOOT_SCRIPT_LAUNCH" "runtime.sh" "sequential extraction phase: packages" || true
    SPRUCE_FIRSTBOOT_UI=1 "/mnt/SDCARD/spruce/scripts/firstboot.sh"
    firstboot_rc="$?"
    case "$firstboot_rc" in
        0)
            firstboot_result="success"
            ;;
        2)
            firstboot_result="warning"
            ;;
        *)
            firstboot_result="failed"
            ;;
    esac

    "$SYSTEM_EMIT" process runtime "FIRSTBOOT_SCRIPT_RESULT" "runtime.sh" "returned from firstboot.sh status=$firstboot_result" || true

    if [ "$firstboot_rc" -eq 0 ] || [ "$firstboot_rc" -eq 2 ]; then
        foreground_unpack_ok=0
        if run_unpacker_foreground \
            "FIRSTBOOT_FOREGROUND_LAUNCH" \
            "sequential extraction after firstboot" \
            "FIRSTBOOT_FOREGROUND_RESULT" \
            "firstboot foreground run" \
            "0" \
            "1" \
            "1"; then
            foreground_unpack_ok=1
        fi

        if [ "$foreground_unpack_ok" -eq 1 ] || [ "$firstboot_rc" -eq 2 ]; then
            if [ "$foreground_unpack_ok" -ne 1 ] && [ "$firstboot_rc" -eq 2 ]; then
                log_message "Firstboot: Showing warning completion UX despite foreground unpack result because firstboot returned warning."
            fi
            display_image_and_text "$WIKI_ICON" 35 25 "Check out the spruce wiki on our GitHub page for tips and FAQs!" 75
            sleep 3
            if [ "$firstboot_rc" -eq 2 ]; then
                display_image_and_text "$SPRUCE_ICON" 35 25 "Spruce setup completed with warnings.\nSome themes may need attention." 75
            else
                display_image_and_text "$HAPPY_ICON" 35 25 "Happy gaming.........." 75
            fi
            sleep 3
        else
            log_message "Firstboot: Skipping completion UX because foreground unpack did not finish cleanly."
        fi
    else
        log_message "Firstboot: firstboot.sh returned non-zero; skipping completion UX."
    fi
else
    run_unpacker_foreground \
        "FOREGROUND_LAUNCH" \
        "non-first_boot path" \
        "FOREGROUND_RESULT" \
        "foreground run" \
        "1" \
        "0" \
        "0"
fi

# Run upgrade scripts on first boot after PC installer (or if flag was left by a failed restore)
if flag_check "run_upgrades"; then
    log_message "run_upgrades flag detected, running upgrade scripts"
    run_upgrade_scripts
    flag_remove "run_upgrades"
fi

/mnt/SDCARD/spruce/scripts/set_up_swap.sh &

launch_startup_watchdogs
"$SYSTEM_EMIT" process runtime "STARTUP_WATCHDOGS_LAUNCHED" "runtime.sh" "startup_watchdogs launched" || true

# check whether to auto-resume into a game
if flag_check "save_active"; then
    if auto_resume_game; then
        log_message "Auto Resume contract: staged intent in runtime helper; principal.sh owns execution."
    else
        log_message "Auto Resume contract: staging failed; continuing with normal runtime/menu path."
    fi
    flag_remove "save_active"
else
    log_message "Auto Resume skipped (no save_active flag)"
fi

developer_mode_task &
update_checker &
# update_notification

# Initialize CPU settings
set_smart

# Set up the boot_to action prior to getting into the principal loop
set_up_boot_action

# start main loop
log_message "Starting main loop"
/mnt/SDCARD/spruce/scripts/principal.sh
