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

[ "$LED_PATH" != "not applicable" ] && echo mmc0 > "$LED_PATH"/trigger

export HOME="/mnt/SDCARD"

rotate_logs
log_file="/mnt/SDCARD/Saves/spruce/spruce.log" # Resetting log file location
log_message "---------Starting up---------"

run_sd_card_fix_if_triggered    # do this before anything else
set_performance
device_init
# Check if WiFi is enabled and bring up network services if so
enable_or_disable_wifi &

# Flag cleanup
flag_remove "log_verbose" &
flag_remove "low_battery" &
flag_remove "in_menu" &

unstage_archives_wanted

# Check for first_boot flags and run Unpacker accordingly
if flag_check "first_boot_${PLATFORM}"; then
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh --silent &
    log_message "Unpacker started silently in background due to first_boot flag"
else
    /mnt/SDCARD/spruce/scripts/archiveUnpacker.sh
fi

check_and_handle_firmware_app &
check_and_hide_update_app &

# check whether to run first boot procedure
if flag_check "first_boot_${PLATFORM}"; then
    "/mnt/SDCARD/spruce/scripts/firstboot.sh"
fi

/mnt/SDCARD/spruce/scripts/set_up_swap.sh &

launch_startup_watchdogs

# check whether to auto-resume into a game
if flag_check "save_active"; then
    log_message "save_active flag detected. Autoresuming game."

    # Ensure device is properly initialized (volume, wifi, etc) before launching auto-resume
    /mnt/SDCARD/App/PyUI/launch.sh -startupInitOnly True

    # moving rather than copying prevents you from repeatedly reloading into a corrupted NDS save state;
    # copying is necessary for repeated save+shutdown/autoresume chaining though and is preferred when safe.
    MOVE_OR_COPY=cp
    if grep -q "Roms/NDS" "${FLAGS_DIR}/lastgame.lock"; then MOVE_OR_COPY=mv; fi

    # move command to cmd_to_run.sh so game switcher can work correctly
    $MOVE_OR_COPY "/mnt/SDCARD/spruce/flags/lastgame.lock" /tmp/cmd_to_run.sh && sync

    sleep 4
    nice -n -20 /tmp/cmd_to_run.sh &> /dev/null
    rm -f /tmp/cmd_to_run.sh # remove tmp command file after game exit; otherwise the game will load again in principal.sh later
    log_message "Auto Resume executed"
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
BOOT_ACTION="$(get_config_value '.menuOptions."System Settings".bootTo.selected' "spruceUI")"
if ! flag_check "save_active"; then
    log_message "Selected boot action is $BOOT_ACTION."
    case "$BOOT_ACTION" in
        "Random Game")
            echo "\"/mnt/SDCARD/App/RandomGame/random.sh\"" > /tmp/cmd_to_run.sh
            ;;
        "Game Switcher")
            touch /mnt/SDCARD/App/PyUI/pyui_gs_trigger
            ;;
        "Splore")
            log_message "Attempting to boot into Pico-8. Checking for binaries"
            if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
                PICO8_EXE="pico8_dyn"
            else
                PICO8_EXE="pico8_64"
            fi
            if [ -f "/mnt/SDCARD/BIOS/pico8.dat" ] && [ -f "/mnt/SDCARD/BIOS/$PICO8_EXE" ]; then
                echo "\"/mnt/SDCARD/Emu/.emu_setup/standard_launch.sh\" \"/mnt/SDCARD/Roms/PICO8/-=☆ Launch Splore ☆=-.splore\"" > /tmp/cmd_to_run.sh
            else
                log_message "Pico-8 binaries not found; booting to spruceUI instead."
            fi
            ;;
    esac
fi

flag_remove "save_active"

# start main loop
log_message "Starting main loop"
/mnt/SDCARD/spruce/scripts/principal.sh
