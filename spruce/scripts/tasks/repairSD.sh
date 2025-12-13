#!/bin/sh

EXPERT_ICON="/mnt/SDCARD/Themes/SPRUCE/icons/app/expertappswitch.png"
LOG_LOCATION="/mnt/SDCARD/SDCARD_REPAIR.log"
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
    display_image_and_text "$EXPERT_ICON" 30 25 "$msg" 75
    if confirm 60; then
        log_message "User confirmed running repairSD.sh."
        touch /mnt/SDCARD/FIX_MY_SDCARD
        sync
        poweroff
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

tmp_display() {
    text="$1"

    tmp_display_kill

    command="LD_LIBRARY_PATH=$LD_LIBRARY_PATH /tmp/sdfix/display_text.elf"
    command="$command $DISPLAY_WIDTH $DISPLAY_HEIGHT $DISPLAY_ROTATION"
    command="$command /tmp/sdfix/bg.png \"$text\" 0 30 50 middle $TEXT_WIDTH eb db b2 /tmp/sdfix/nunwen.ttf 7f 7f 7f 0 1.0 /tmp/sdfix/expertappswitch.png 0.20 center middle"

    echo "displaying: $command"
    eval "$command" &
    DISPLAY_PID=$!
}

tmp_display_kill() {
    [ -n "$DISPLAY_PID" ] && kill "$DISPLAY_PID" 2>/dev/null
    sleep 0.1
}

tmp_read_only_check() {
    echo "Performing read-only check"
    SD_or_sd=$(mount | grep -q sdcard && echo "sdcard" || echo "SDCARD")
    echo "Device uses /mnt/$SD_or_sd for its SD card path"
    MNT_LINE=$(mount | grep "$SD_or_sd")
    if [ -n "$MNT_LINE" ]; then
        echo "mount line for SD card: $MNT_LINE" -v
        MNT_STATUS=$(echo "$MNT_LINE" | cut -d'(' -f2 | cut -d',' -f1)
        if [ "$MNT_STATUS" = "ro" ] && [ -n "$SD_DEV" ]; then
            echo "SD card is mounted as RO. Attempting to remount."
            mount -o remount,rw "$SD_DEV" /mnt/"$SD_or_sd"
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

    {
        tmp_read_only_check
        tmp_set_performance
        rm -f /mnt/SDCARD/FIX_MY_SDCARD

        mkdir -p /tmp/sdfix
        cp "$BIN_DIR/fsck.fat" /tmp/sdfix/ && echo "copied fsck.fat to /tmp/sdfix/"
        cp "$BIN_DIR/display_text.elf" /tmp/sdfix/ && echo "copied display_text.elf to /tmp/sdfix/"
        cp "$EXPERT_ICON" /tmp/sdfix/ && echo "copied expertappswitch.png to /tmp/sdfix/"
        cp "$FONT" /tmp/sdfix/ && echo "copied nunwen.ttf to /tmp/sdfix/"
        cp "$BG_IMAGE" "/tmp/sdfix/bg.png" && echo "copied background image to /tmp/sdfix/"
        chmod 777 /tmp/sdfix/display_text.elf
        chmod 777 /tmp/sdfix/fsck.fat

        tmp_display "Attempting to repair SD card. This may take some time."
        
        if umount "$SD_DEV"; then
            echo "$SD_DEV unmounted successfully."
        else
            echo "Unable to unmount $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
            sleep 10
            poweroff
        fi
        
        if /tmp/sdfix/fsck.fat -av "$SD_DEV"; then
            echo "fsck.fat has been run on $SD_DEV and appears successful."

            msg="SD card repair appears to have been successful."
            if [ "$PLATFORM" = "A30" ]; then
                msg="$msg After 10 seconds, your device will shut itself down."
                cmd=poweroff
            else
                msg="$msg After 10 seconds, your device will reboot."
                cmd=reboot
            fi
            tmp_display "$msg"
            sleep 10
            sync
            $cmd
        else
            echo "fsck.fat reported errors. Unable to repair $SD_DEV."
            tmp_display "SD card repair attempt failed. Sorry! Your device will shut down in 10 seconds. Please eject your SD card and attempt a repair using your PC instead."
            sleep 10
            sync
            poweroff
        fi

    tmp_display_kill
    sync
    poweroff
    while true; do : ; done

    } > "$LOG_LOCATION" 2>&1
fi