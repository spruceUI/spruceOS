#!/bin/sh

# TODO: miyoo mini support
# TODO: opt out with a tmp_confirm() ?

EXPERT_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/expertappswitch.png"
TMP_LOG_PATH=/tmp/SDCARD_REPAIR.log
FINAL_LOG_PATH="/mnt/SDCARD/SDCARD_REPAIR.log"
FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"


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

INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"sun8i"*)
        PLATFORM="A30"
        LD_LIBRARY_PATH="/usr/miyoo/lib:/usr/lib:/lib"
        SD_DEV="/dev/mmcblk0p1"
        BIN_DIR="/mnt/SDCARD/spruce/bin"
        MAX_FREQ=1344000
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
        TEXT_WIDTH=600
        DISPLAY_WIDTH=640
        DISPLAY_HEIGHT=480
        DISPLAY_ROTATION=270
        ;;
    *"0xd05"*)
        PLATFORM="Flip"
        LD_LIBRARY_PATH="/usr/miyoo/lib:/usr/lib:/lib"
        SD_DEV="/dev/mmcblk1p1"
        BIN_DIR="/mnt/SDCARD/spruce/bin64"
        MAX_FREQ=1800000
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
        TEXT_WIDTH=600
        DISPLAY_WIDTH=640
        DISPLAY_HEIGHT=480
        DISPLAY_ROTATION=0
        ;;
    *"0xd04"*)
        PLATFORM="Pixel2"
        LD_LIBRARY_PATH="/usr/lib:/lib:/usr/lib/compat"
        SD_DEV="/dev/mmcblk0p3"
        BIN_DIR="/mnt/SDCARD/spruce/bin64"
        MAX_FREQ=1416000
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
        TEXT_WIDTH=600
        DISPLAY_WIDTH=640
        DISPLAY_HEIGHT=480
        DISPLAY_ROTATION=0
        ;;
    *"TG3040"*)
        PLATFORM="Brick"
        LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
        SD_DEV="/dev/mmcblk1p1"
        BIN_DIR="/mnt/SDCARD/spruce/bin64"
        MAX_FREQ=1800000
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree.png"
        TEXT_WIDTH=960
        DISPLAY_WIDTH=1024
        DISPLAY_HEIGHT=768
        DISPLAY_ROTATION=0
        ;;
    *"TG5040"*)
        PLATFORM="SmartPro"
        LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
        SD_DEV="/dev/mmcblk1p1"
        BIN_DIR="/mnt/SDCARD/spruce/bin64"
        MAX_FREQ=1800000
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png" 
        TEXT_WIDTH=1200
        DISPLAY_WIDTH=1280
        DISPLAY_HEIGHT=720
        DISPLAY_ROTATION=0
        ;;
    *"TG5050"*)
        PLATFORM="SmartProS"
        LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib"
        SD_DEV="/dev/mmcblk1p1"
        BIN_DIR="/mnt/SDCARD/spruce/bin64"
        MAX_FREQ=1800000
        BG_IMAGE="/mnt/SDCARD/spruce/imgs/bg_tree_wide.png"
        TEXT_WIDTH=1200
        DISPLAY_WIDTH=1280
        DISPLAY_HEIGHT=720
        DISPLAY_ROTATION=0
        ;;
esac

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

tmp_display() {
    text="$1"

    tmp_display_kill

    command="LD_LIBRARY_PATH=$LD_LIBRARY_PATH /tmp/sdfix/display_text.elf"
    command="$command $DISPLAY_WIDTH $DISPLAY_HEIGHT $DISPLAY_ROTATION"
    command="$command /tmp/sdfix/bg.png \"$text\" 0 30 50 middle $TEXT_WIDTH eb db b2 /tmp/sdfix/nunwen.ttf 7f 7f 7f 0 1.0"

    echo "displaying: $command"
    eval "$command" &
    DISPLAY_PID=$!
}

tmp_display_kill() {
    [ -n "$DISPLAY_PID" ] && kill "$DISPLAY_PID" 2>/dev/null
    sleep 0.1
}

tmp_kill_boot_scripts() {
    echo "Attempting to kill any boot scripts."
    for script in main tee runmiyoo.sh runtrimui.sh runmagicx.sh updater runtime.sh ; do
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
    echo "Locking CPU governor to performance with maximum frequency $MAX_FREQ"
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo performance >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo "$MAX_FREQ" >/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
}


  #############################
##### ACTUAL REPAIR PROCESS #####
  #############################

if [ "$1" = "run" ]; then

    mkdir -p /tmp/sdfix     # do this first so the tmp log path is valid
    cd /tmp/sdfix

    {
        tmp_blink
        tmp_kill_boot_scripts
        tmp_read_only_check
        tmp_set_performance
        rm -f /mnt/SDCARD/FIX_MY_SDCARD

        cp "$BIN_DIR/fsck.fat" /tmp/sdfix/ && echo "copied fsck.fat to /tmp/sdfix/"
        cp "$BIN_DIR/display_text.elf" /tmp/sdfix/ && echo "copied display_text.elf to /tmp/sdfix/"
        cp "$EXPERT_ICON" /tmp/sdfix/ && echo "copied expertappswitch.png to /tmp/sdfix/"
        cp "$FONT" /tmp/sdfix/ && echo "copied nunwen.ttf to /tmp/sdfix/"
        cp "$BG_IMAGE" "/tmp/sdfix/bg.png" && echo "copied background image to /tmp/sdfix/"
        chmod 777 /tmp/sdfix/display_text.elf
        chmod 777 /tmp/sdfix/fsck.fat

        tmp_display "Attempting to repair SD card. This may take some time."

        tmp_debug_info    # uncomment to see `ps` and `mount` outputs in your log

        if umount "$SD_DEV"; then
            echo "$SD_DEV unmounted successfully."
        else
            echo "Unable to unmount $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
            sleep 10
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            poweroff
        fi
        
        /tmp/sdfix/fsck.fat -av "$SD_DEV"
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
            mount "$SD_DEV" /mnt/SDCARD 2>/dev/null
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
            mount "$SD_DEV" /mnt/SDCARD 2>/dev/null
            cp "$TMP_LOG_PATH" "$FINAL_LOG_PATH"
            sync
            [ "$PLATFORM" = "A30" ] && poweroff || reboot

        else
            echo "fsck.fat reported errors. Unable to repair $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
            sleep 10
            mount "$SD_DEV" /mnt/SDCARD 2>/dev/null
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