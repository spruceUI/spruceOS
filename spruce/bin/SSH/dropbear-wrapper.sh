#!/bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Set the working directory to /mnt/SDCARD for all commands
cd /mnt/SDCARD

# TODO: this probably doesn't work outside the a30?
if [ "$SSH_ORIGINAL_COMMAND" = "/usr/libexec/sftp-server" ]; then
    if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
        GESFTPSERVER="/mnt/SDCARD/spruce/bin/gesftpserver"
    else
        GESFTPSERVER="/mnt/SDCARD/spruce/bin64/gesftpserver"
    fi
    if [ -x "$GESFTPSERVER" ]; then
        exec $GESFTPSERVER
    else
        exit 1
    fi
elif [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    exec $SSH_ORIGINAL_COMMAND
else
    exec /bin/sh
fi
