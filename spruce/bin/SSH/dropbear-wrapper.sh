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
        exec "$GESFTPSERVER"
    else
        exit 1
    fi
elif [ -n "$SSH_ORIGINAL_COMMAND" ]; then
    # Hand the command to a shell rather than exec'ing it unquoted, which is what
    # sshd does too. Unquoted, the string is word-split and exec'd directly, so
    # every shell metacharacter survives as a literal argument: "echo one; echo
    # two" printed "one; echo two", and "ls /mnt/SDCARD | head -3" passed "|" and
    # "-3" to ls as arguments. Word splitting also glob-expanded against the
    # /mnt/SDCARD we just cd'd into rather than the caller's intent.
    exec /bin/sh -c "$SSH_ORIGINAL_COMMAND"
else
    exec /bin/sh
fi
