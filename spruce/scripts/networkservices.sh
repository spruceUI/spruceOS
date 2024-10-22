#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/SSH/dropbearFunctions.sh
. /mnt/SDCARD/spruce/bin/Samba/sambaFunctions.sh
. /mnt/SDCARD/spruce/bin/SFTPGo/sftpgoFunctions.sh
. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh

connect_services() {
    
    while true; do
        if ifconfig wlan0 | grep -qE "inet |inet6 "; then
            
            # SFTPGo check
            if flag_check "sftpgo" && ! pgrep "sftpgo" > /dev/null; then
                # Flag exists but service is not running, so start it...
                log_message "Network services: SFTPGo detected not running, starting..."
                start_sftpgo_process
            fi

            # SSH check
            if flag_check "dropbear" && ! pgrep "dropbear" > /dev/null; then
                # Flag exists but service is not running, so start it...
                log_message "Network services: Dropbear detected not running, starting..."
                start_dropbear_process
            fi
            
            # Samba check
            if flag_check "samba" && ! pgrep "smbd" > /dev/null; then
                # Flag exists but service is not running, so start it...
                log_message "Network services: Samba detected not running, starting..."
                start_samba_process
            fi
            
            # Syncthing check
            if flag_check "syncthing" && ! pgrep "syncthing" > /dev/null; then
                # Flag exists but service is not running, so start it...
                log_message "Network services: Syncthing detected not running, starting..."
                start_syncthing_process
            fi
            
            break
            
        fi
        sleep 1
    done
}

# Attempt to bring up the network services if WIFI is connected
connect_services
