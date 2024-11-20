#!/bin/sh

# Set the working directory to /mnt/SDCARD for all commands
cd /mnt/SDCARD

if [ "$SSH_ORIGINAL_COMMAND" = "/usr/libexec/sftp-server" ]; then
    if [ -x "/mnt/SDCARD/miyoo/app/gesftpserver" ]; then
		exec /mnt/SDCARD/miyoo/app/gesftpserver
    else
        exit 1
    fi
elif [ -n "$SSH_ORIGINAL_COMMAND" ]; then
	exec $SSH_ORIGINAL_COMMAND
else
	exec /bin/sh
fi
