#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh
. /mnt/SDCARD/spruce/bin/SSH/dropbearFunctions.sh

EMUFRESH="/mnt/SDCARD/spruce/scripts/emufresh_md5_multi.sh"

if flag_check "developer_mode" || flag_check "designer_mode"; then
   log_message "Developer mode enabled"
    # Turn off idle monitors
    update_setting "idlemon_in_game" "Off"
    update_setting "idlemon_in_menu" "Off"
    
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
fi


if flag_check "designer_mode"; then
    log_message "Designer mode enabled"
    if [ -f "$EMUFRESH" ]; then
        "$EMUFRESH" -showall
    elif [ -f "$EMUFRESH.bak" ]; then
        "$EMUFRESH.bak" -showall
    fi
    # Changing the name to break future calls.
    mv "$EMUFRESH" "$EMUFRESH.bak"
fi

# Restore if neither mode is enabled
if ! flag_check "designer_mode" && ! flag_check "developer_mode"; then

    # Restore EMUFRESH if it exists
    if [ -f "$EMUFRESH.bak" ]; then
        mv "$EMUFRESH.bak" "$EMUFRESH"
    fi
fi
