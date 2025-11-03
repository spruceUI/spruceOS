#!/bin/sh

SD2_DEV="$1"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_sd2() {
    log_message "*** sd2_watchdog.sh: $1"
}

get_mountpoint() {
    cat /proc/mounts | grep "$SD2_DEV" | cut -d " " -f 2
}

do_mounts() {
    log_sd2 "Binding Roms to the second SD card"
    [ -d "/media/sdcard1/Roms" ] mount --bind /media/sdcard1/Roms /mnt/SDCARD/Roms
}

log_sd2 "Starting second SD card watchdog for $SD2_DEV"
mounted=0
while true; do
    if [ ! -b "$SD2_DEV" ]; then
        mounted=0
        sleep 10s
        continue
    fi
    
    if [ "$mounted" -eq 1 ]; then
        /mnt/SDCARD/spruce/bin64/inotifywait "$SD2_DEV" > /dev/null
        log_sd2 "Second SD card probably removed"
        continue
    fi
    
    log_sd2 "Second SD detected"
    mountpoint=$(get_mountpoint)
    if [ "$mountpoint" != "/media/sdcard1" ]; then
        log_sd2 "Remounting second SD card at the proper path"
        umount "$SD2_DEV"
        mount "$SD2_DEV" "/media/sdcard1"
    fi
    
    [ "$mounted" -ne 1 ] && do_mounts
    mounted=1
done

