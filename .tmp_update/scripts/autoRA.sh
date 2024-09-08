#!/bin/sh

if test -f /mnt/SDCARD/.tmp_update/flags/.save_active; then
    keymon &
    /mnt/SDCARD/.tmp_update/flags/.lastgame  &> /dev/null
    /mnt/SDCARD/.tmp_update/scripts/select.sh  &> /dev/null
    return
# else
#    /mnt/SDCARD/.tmp_update/scripts/principal.sh
fi
