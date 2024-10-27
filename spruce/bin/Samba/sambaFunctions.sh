#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

samba_check(){
    if setting_check "samba"; then
        start_samba_process
    fi
}

start_samba_process(){
    log_message "Starting Samba..."
    
	# Set the LD_LIBRARY_PATH
	export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/bin/Samba/lib:$LD_LIBRARY_PATH"

	# Create necessary directories
	mkdir -p /tmp/samba/private
	mkdir -p /tmp/samba/lock
	mkdir -p /tmp/samba/run

	# Set the Samba password for the root user
	PASSWORD="tina"
	echo -ne "$PASSWORD\n$PASSWORD\n" | /mnt/SDCARD/spruce/bin/Samba/bin/smbpasswd -c /mnt/SDCARD/spruce/bin/Samba/config/smb.conf -s -a root

	# Start the Samba daemon
	rm /tmp/samba/run/smbd-smb.conf.pid
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH" /mnt/SDCARD/spruce/bin/Samba/bin/smbd -s /mnt/SDCARD/spruce/bin/Samba/config/smb.conf -D
}

stop_samba_process(){
    log_message "Shutting down Samba..."
    kill $(pgrep smbd)
}
