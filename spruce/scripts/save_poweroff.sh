#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh


# kill principal and runtime first so no new app / MainUI will be loaded anymore
killall -q -15 runtime.sh
killall -q -15 principal.sh

# Ensure PyUI message writer can run
killall -q -9 MainUI
sleep 0.5


if [ "$PLATFORM" = "A30" ]; then
    BIN_PATH="/mnt/SDCARD/spruce/bin"
    SET_OR_CSET="set"
    NAME_QUALIFIER=""
    AMIXER_CONTROL="'Soft Volume Master'"
else
    BIN_PATH="/mnt/SDCARD/spruce/bin64"
    SET_OR_CSET="cset"
    NAME_QUALIFIER="name="
    AMIXER_CONTROL="'SPK Volume'"
fi

FLAGS_DIR="/mnt/SDCARD/spruce/flags"

BG_TREE="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"

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

vibrate &

#is this a30 specific? get errors in output on flip
# Save system brightness level
if flag_check "sleep.powerdown"; then
    cp /mnt/SDCARD/spruce/settings/tmp_sys_brightness_level /mnt/SDCARD/spruce/settings/sys_brightness_level
else
    cat "$DEVICE_BRIGHTNESS_PATH" >/mnt/SDCARD/spruce/settings/sys_brightness_level
fi

# kill lid watchdog so that closing the lid doesn't interrupt the save/shutdown procedure
pgrep -f "lid_watchdog.sh" | xargs -r kill

# notify user with led
[ "$LED_PATH" != "not applicable" ] && echo heartbeat > "$LED_PATH"/trigger

# kill enforceSmartCPU first so no CPU setting is changed during shutdown
killall -q -15 enforceSmartCPU.sh

# kill app if not emulator is running
if cat /tmp/cmd_to_run.sh | grep -q -v -e '/mnt/SDCARD/Emu' -e '/media/sdcard0/Emu' -e '/mnt/SDCARD/Emus'; then
    kill_current_process
    # remove lastgame flag to prevent loading any App after next boot
    rm "${FLAGS_DIR}/lastgame.lock"
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
    killall -q -15 PPSSPPSDL_TrimUI
    killall -q -15 PPSSPPSDL_$PLATFORM
else
    killall -q -15 ra64.miyoo
    killall -q -15 ra32.miyoo
    killall -q -15 retroarch
    killall -q -15 retroarch-flip
    killall -q -15 ra64.trimui_$PLATFORM
    killall -q -15 drastic32
    killall -q -15 drastic64
    killall -q -15 pico8_dyn
    killall -q -15 pico8_64
    killall -q -15 flycast
    killall -q -15 yabasanshiro
    killall -q -15 yabasanshiro.trimui
    killall -q -15 mupen64plus
fi

# wait until emulator exit
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
    killall -q -0 mupen64plus; do
    sleep 0.3
done

start_pyui_message_writer

# Display appropriate image and message depending on whether it's a forced safe shutdown, or else whether user is in-game or in-menu.
if flag_check "forced_shutdown"; then
    display_image_and_text "/mnt/SDCARD/spruce/imgs/save.png" 33 10 "Battery level is below 1%. Shutting down to prevent progress loss." 60 50
    flag_remove "forced_shutdown"
else
    display_image_and_text "/mnt/SDCARD/spruce/imgs/save.png" 33 10 "Saving and shutting down... Please wait a moment." 60 50
fi

dim_screen &

# Set flag to trigger autoresume on boot if appropriate
if flag_check "in_menu"; then
    flag_remove "save_active"
else
    flag_add "save_active"
fi

syncthing_enabled="$(get_config_value '.menuOptions."Network Settings".enableSyncthing.selected' "False")"
if [ "$syncthing_enabled" = "True" ] && flag_check "emulator_launched"; then
    log_message "Syncthing is enabled, WiFi connection needed"

    # This seems specific to one device, is it a30?
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

flag_remove "sleep.powerdown"
flag_remove "emulator_launched"

# Save current sound settings
if flag_check "sleep.powerdown"; then
    amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $(cat /mnt/SDCARD/spruce/settings/tmp_sys_volume_level)
fi
alsactl store


#Let user read any messages
sleep 3

# kill MainUI
killall -q -9 MainUI

# wait until emulator or MainUI exit
while killall -q -0 MainUI; do
    sleep 0.3
done

# sync files and power off device
sync
poweroff

