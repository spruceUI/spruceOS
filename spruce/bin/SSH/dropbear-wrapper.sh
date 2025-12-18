#!/bin/sh

# Set the working directory to /mnt/SDCARD for all commands
cd /mnt/SDCARD

# TODO: this probably doesn't work outside the a30?
if [ "$SSH_ORIGINAL_COMMAND" = "/usr/libexec/sftp-server" ]; then
    if [ "$PLATFORM" = "A30" ]; then
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
    if [ "$BRAND" = "TrimUI" ]; then
        export LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
    elif [ "$PLATFORM" = "Flip" ]; then
        export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
    fi
    case "$PLATFORM" in
		"A30") APP_PATH="/mnt/SDCARD/miyoo/app" ;;
		"Flip") APP_PATH="/mnt/SDCARD/miyoo355/app" ;;
		"Brick" | "SmartPro") APP_PATH="/mnt/SDCARD/trimui/app" ;;
    esac
    export PATH="$APP_PATH:/usr/sbin:/usr/bin:/sbin:/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    exec /bin/sh
fi
