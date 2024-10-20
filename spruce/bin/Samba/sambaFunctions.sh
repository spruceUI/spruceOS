#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

samba_check(){
    if flag_check "samba"; then
        start_samba_process
    fi
}

start_samba_process(){
    log_message "Starting Samba..."
    
	# Set the LD_LIBRARY_PATH
	export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/bin/Samba/lib:$LD_LIBRARY_PATH"

	# Create necessary directories
	mkdir -p /mnt/SDCARD/spruce/bin/Samba/runtime/private
	mkdir -p /mnt/SDCARD/spruce/bin/Samba/runtime/lock
	mkdir -p /mnt/SDCARD/spruce/bin/Samba/runtime/run

	# Set the Samba password for the root user
	PASSWORD="tina"
	echo -ne "$PASSWORD\n$PASSWORD\n" | /mnt/SDCARD/spruce/bin/Samba/bin/smbpasswd -c /mnt/SDCARD/spruce/bin/Samba/config/smb.conf -s -a root

	# Start the Samba daemon
	rm /mnt/SDCARD/spruce/bin/Samba/runtime/run/smbd-smb.conf.pid
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH" /mnt/SDCARD/spruce/bin/Samba/bin/smbd -s /mnt/SDCARD/spruce/bin/Samba/config/smb.conf --no-process-group -D
	flag_add "samba"
}

stop_samba_process(){
    log_message "Shutting down Samba..."	
    kill -9 $(pgrep smbd)
    rm /mnt/SDCARD/spruce/bin/Samba/runtime/run/smbd-smb.conf.pid
    flag_remove "samba"
}
