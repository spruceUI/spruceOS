#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh

if flag_check "developer_mode"; then
    log_message "Developer mode enabled"

    sh /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh reapply

    # Enable certain network services
    update_setting "samba" "on"
    update_setting "dropbear" "on"
    update_setting "sftpgo" "on"

    # Dropbear first time setup and start
    first_time_setup &
fi
