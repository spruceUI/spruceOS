#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

CONFIG_FILE="/mnt/SDCARD/App/Samba/config.json"

samba_check(){
    if flag_check "samba"; then
        start_samba_process
    else
        sed -i 's|- On|- Off|' $CONFIG_FILE
    fi
}

start_samba_process(){
    log_message "Starting Samba..."
    
	# Set the LD_LIBRARY_PATH
	export LD_LIBRARY_PATH="/mnt/SDCARD/App/Samba/lib:$LD_LIBRARY_PATH"

	# Create necessary directories
	mkdir -p /mnt/SDCARD/App/Samba/runtime/private
	mkdir -p /mnt/SDCARD/App/Samba/runtime/lock
	mkdir -p /mnt/SDCARD/App/Samba/runtime/run

	# Set the Samba password for the root user
	PASSWORD="tina"
	echo -ne "$PASSWORD\n$PASSWORD\n" | /mnt/SDCARD/App/Samba/bin/smbpasswd -c /mnt/SDCARD/App/Samba/config/smb.conf -s -a root

	# Start the Samba daemon
	rm /mnt/SDCARD/App/Samba/runtime/run/smbd-smb.conf.pid
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH" /mnt/SDCARD/App/Samba/bin/smbd -s /mnt/SDCARD/App/Samba/config/smb.conf --no-process-group -D

    sed -i 's|- Off|- On|' "$CONFIG_FILE"
    sed -i 's|"#label"|"label"|' "$CONFIG_FILE"
}