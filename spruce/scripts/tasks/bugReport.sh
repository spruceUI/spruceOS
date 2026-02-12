#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

output7z=/mnt/SDCARD/bug_report.7z

if [ -f $output7z ] ; then
    rm $output7z
fi

7zr a -spf2 "$output7z" \
            -i'!/mnt/SDCARD/Saves/*.json' \
            -i'!/mnt/SDCARD/Saves/spruce/*.log' \
            -i'!/mnt/SDCARD/Saves/spruce/*.json' \
            -i'!/mnt/SDCARD/RetroArch/.retroarch/logs/*'

log_message "Debug: Logs and configs saved to ${output7z}"
