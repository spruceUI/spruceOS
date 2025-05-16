#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

BIN_PATH="/mnt/SDCARD/spruce/bin"
if [ ! "$PLATFORM" = "A30"]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
fi
SET_OR_CSET="cset"
[ "$PLATFORM" = "A30" ] && SET_OR_CSET="set"
NAME_QUALIFIER="name="
[ "$PLATFORM" = "A30" ] && NAME_QUALIFIER=""
AMIXER_CONTROL="'SPK Volume'"
[ "$PLATFORM" = "A30" ] && AMIXER_CONTROL="'Soft Volume Master'"
FLAGS_DIR="/mnt/SDCARD/spruce/flags"

[ "$PLATFORM" = "SmartPro" ] && BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" || BG_TREE="/mnt/SDCARD/spruce/imgs/bg_tree.png"

kill_current_process() {
    pid=$(ps | grep cmd_to_run | grep -v grep | sed 's/[ ]\+/ /g' | cut -d' ' -f2)
    ppid=$pid
    while [ "" != "$pid" ]; do
        ppid=$pid
        pid=$(pgrep -P $ppid)
    done

    if [ "" != "$ppid" ]; then
        kill -9 $ppid
    fi
}

vibrate

# Save system brightness level
if flag_check "sleep.powerdown"; then
    cp /mnt/SDCARD/spruce/settings/tmp_sys_brightness_level /mnt/SDCARD/spruce/settings/sys_brightness_level
else
    cat "$DEVICE_BRIGHTNESS_PATH" >/mnt/SDCARD/spruce/settings/sys_brightness_level
fi

if pgrep -f gameswitcher.sh >/dev/null; then
    # pause game switcher
    killall -q -19 switcher
    # remove lastgame flag to prevent loading any App after next boot
    flag_remove "lastgame"
    # add flag to load game switcher after next boot
    flag_add "gs"
    # display blank tree screen while shutting down
    display -i "$BG_TREE"
    dim_screen &
fi

# Check if MainUI or PICO8 is running and skip_shutdown_confirm is not set
if flag_check "in_menu" || pgrep "pico8_dyn" || pgrep "pico8_64" >/dev/null; then
    if setting_get "skip_shutdown_confirm" || flag_check "forced_shutdown"; then
        # If skip_shutdown_confirm is set, proceed directly with shutdown
        rm "${FLAGS_DIR}/lastgame.lock"
        if flag_check "forced_shutdown"; then
            display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png" -t "Battery level is below 1%. Shutting down to prevent progress loss."
            flag_remove "forced_shutdown"
        else
            display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png"
        fi
        dim_screen &
    else
        # Pause MainUI or pico8
        killall -q -19 MainUI
        killall -q -19 pico8_dyn
        killall -q -19 pico8_64

        if ! flag_check "sleep.powerdown"; then
            # Show confirmation screen
            display --text "Are you sure you want to shutdown?" --image "$BG_TREE" --confirm

            # Wait for user confirmation
            if confirm 30 0; then
                rm "${FLAGS_DIR}/lastgame.lock"
                display -i "$BG_TREE"
                dim_screen &
            else
                display_kill
                # Resume MainUI or pico8_dyn
                killall -q -18 MainUI
                killall -q -18 pico8_dyn
                killall -q -18 pico8_64
                return 0
            fi
        else
            # If sleep powerdown, proceed with shutdown
            rm "${FLAGS_DIR}/lastgame.lock"
        fi
    fi
fi

# notify user with led
echo heartbeat > "$LED_PATH"/trigger

# kill principle and runtime first so no new app / MainUI will be loaded anymore
killall -q -15 runtime.sh
killall -q -15 principal.sh

# kill enforceSmartCPU first so no CPU setting is changed during shutdown
killall -q -15 enforceSmartCPU.sh

# kill app if not emulator is running
if cat /tmp/cmd_to_run.sh | grep -q -v -e '/mnt/SDCARD/Emu' -e '/media/sdcard0/Emu' -e '/mnt/SDCARD/Emus'; then
    kill_current_process
    # remove lastgame flag to prevent loading any App after next boot
    rm "${FLAGS_DIR}/lastgame.lock"
fi

# kill PICO8 if PICO8 is running
if pgrep "pico8_dyn" >/dev/null; then
    killall -q -15 pico8_dyn
    killall -q -15 pico8_64
fi

# trigger auto save and send kill signal
if pgrep -f "PPSSPPSDL" >/dev/null; then
    {
        # send autosave hot key
        echo 1 314 1 # SELECT down
        echo 1 311 1 # R1 down
        echo 1 311 0 # R1 up
        echo 1 314 0 # SELECT up
        echo 0 0 0   # tell sendevent to exit
    } | $BIN_PATH/sendevent /dev/input/event4
    sleep 1
    killall -q -15 PPSSPPSDL
    killall -q -15 PPSSPPSDL_$PLATFORM
else
    killall -q -15 ra64.miyoo
    killall -q -15 ra32.miyoo
    killall -q -15 retroarch
    killall -q -15 retroarch-flip
    killall -q -15 ra64.trimui_$PLATFORM
    killall -q -15 drastic32
    killall -q -15 drastic64
    killall -q -15 flycast
    killall -q -15 yabasanshiro
    killall -q -15 yabasanshiro.trimui
    killall -q -15 mupen64plus
    killall -q -9 MainUI
fi

# wait until emulator or MainUI exit
while killall -q -0 ra32.miyoo ||
    killall -q -0 ra64.miyoo ||
    killall -q -0 retroarch ||
    killall -q -0 retroarch-flip ||
    killall -q -0 ra64.trimui_$PLATFORM ||
    killall -q -0 PPSSPPSDL ||
    killall -q -0 PPSSPPSDL_$PLATFORM ||
    killall -q -0 drastic32 ||
    killall -q -0 drastic64 ||
    killall -q -0 flycast ||
    killall -q -0 yabasanshiro ||
    killall -q -0 yabasanshiro.trimui ||
    killall -q -0 mupen64plus||
    killall -q -0 MainUI; do
    sleep 0.3
done

# show saving screen
if flag_check "forced_shutdown"; then
    display -i "/mnt/SDCARD/spruce/imgs/bg_tree.png" -t "Battery level is below 1%. Shutting down to prevent progress loss."
    flag_remove "forced_shutdown"
    dim_screen &
elif ! pgrep "display_text.elf" >/dev/null && ! flag_check "sleep.powerdown"; then
    display --icon "/mnt/SDCARD/spruce/imgs/save.png" -t "Saving and shutting down... Please wait a moment."
    dim_screen &
fi

# Created save_active flag
if flag_check "in_menu"; then
    flag_remove "save_active"
else
    flag_add "save_active"
fi

if setting_get "syncthing" && flag_check "emulator_launched"; then
    log_message "Syncthing is enabled, WiFi connection needed"

    # Restore brightness and sound if sleep->powerdown for syncthing
    if flag_check "sleep.powerdown"; then
        cat /mnt/SDCARD/spruce/settings/tmp_sys_brightness_level >/sys/devices/virtual/disp/disp/attr/lcdbl
        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $(cat /mnt/SDCARD/spruce/settings/tmp_sys_volume_level)
    fi
    
    if check_and_connect_wifi; then
        start_syncthing_process
        # Dimming screen before syncthing sync check
        dim_screen &
        /mnt/SDCARD/spruce/bin/Syncthing/syncthing_sync_check.sh --shutdown
    fi

    flag_remove "syncthing_startup_synced"
fi

flag_remove "emulator_launched"

# Save current sound settings
if flag_check "sleep.powerdown"; then
    amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $(cat /mnt/SDCARD/spruce/settings/tmp_sys_volume_level)
fi
alsactl store

flag_remove "sleep.powerdown"

# All processes should have been killed, safe to update time if enabled
/mnt/SDCARD/spruce/scripts/geoip_timesync.sh

# Now that nothing might need it, organize settings file
settings_organize

# sync files and power off device
sync
poweroff
