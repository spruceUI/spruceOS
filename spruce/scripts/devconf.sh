#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/applySetting/settingHelpers.sh

if [ -f "/mnt/SDCARD/developer_mode" ]; then
   
    # Turn off idle monitors
    echo -n Off > /mnt/SDCARD/spruce/settings/idlemon_in_menu 
    echo -n Off > /mnt/SDCARD/spruce/settings/idlemon_in_game
    
    # Enable certain network services
    update_setting "samba" "on"
    update_setting "dropbear" "on"
    update_setting "sftpgo" "on"
    #update_setting "enableNetworkTimeSync" "on"
    
    # App visibility
    /mnt/SDCARD/spruce/scripts/applySetting/showHideApp.sh show /mnt/SDCARD/App/FileManagement/config.json
    
    # Add flag for global use
    flag_add "developer_mode"
    
fi
