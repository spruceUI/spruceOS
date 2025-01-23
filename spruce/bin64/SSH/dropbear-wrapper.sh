#!/bin/sh

# Set the working directory to /mnt/SDCARD for all commands
cd /mnt/SDCARD

# TODO: this probably doesn't work outside the a30?
if [ "$SSH_ORIGINAL_COMMAND" = "/usr/libexec/sftp-server" ]; then
  if [ -x "/mnt/SDCARD/miyoo/app/gesftpserver" ]; then
    exec /mnt/SDCARD/miyoo/app/gesftpserver
  else
    exit 1
  fi
elif [ -n "$SSH_ORIGINAL_COMMAND" ]; then
  exec $SSH_ORIGINAL_COMMAND
else
  if [ "$PLATFORM" = "Brick" ]; then
    export LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
  elif [ "$PLATFORM" = "Flip" ]; then
    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
  fi
  # TODO: what should this be for brick/flip?
  export PATH=/mnt/SDCARD/miyoo/app:/usr/sbin:/usr/bin:/sbin:/bin:/usr/sbin:/usr/bin:/sbin:/bin
  exec /bin/sh
fi
