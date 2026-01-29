#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
	SMB_DIR=/mnt/SDCARD/spruce/bin/Samba
else # aarch64
	SMB_DIR=/mnt/SDCARD/spruce/bin64/Samba
fi

start_samba_process(){
    log_message "Starting Samba..."
	
	export LD_LIBRARY_PATH="$SMB_DIR/lib:$LD_LIBRARY_PATH"

	# Create necessary directories
	mkdir -p /tmp/samba/private
	mkdir -p /tmp/samba/lock
	mkdir -p /tmp/samba/run

	# Set the Samba password for the root user
	PASSWORD="happygaming"
	echo -ne "$PASSWORD\n$PASSWORD\n" | $SMB_DIR/bin/smbpasswd -c $SMB_DIR/config/smb.conf -s -a spruce

	# Start the Samba daemon
	rm /tmp/samba/run/smbd-smb.conf.pid
	LD_LIBRARY_PATH="$LD_LIBRARY_PATH" $SMB_DIR/bin/smbd -s $SMB_DIR/config/smb.conf -D
}

stop_samba_process(){
    log_message "Shutting down Samba..."
    kill $(pgrep smbd)
}
