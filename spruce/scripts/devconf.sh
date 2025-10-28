#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh
. /mnt/SDCARD/spruce/scripts/network/dropbearFunctions.sh

if flag_check "developer_mode"; then
    log_message "Developer mode enabled"
    # Turn off idle monitors
    update_setting "idlemon_in_game" "Off"
    update_setting "idlemon_in_menu" "Off"

    sh /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh reapply

    # Enable certain network services
    update_setting "samba" "on"
    update_setting "dropbear" "on"
    update_setting "sftpgo" "on"
    #update_setting "enableNetworkTimeSync" "on"

    # Dropbear first time setup and start
    first_time_setup &

    # App visibility
    /mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh show /mnt/SDCARD/App/FileManagement/config.json
    /mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh show /mnt/SDCARD/App/ShowOutputTest/config.json
    sed -i 's/"#label"/"label"/' /mnt/SDCARD/App/ThemePacker/config.json
else
    /mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh hide /mnt/SDCARD/App/ShowOutputTest/config.json
    sed -i 's/"label"/"#label"/' /mnt/SDCARD/App/ThemePacker/config.json
fi
