#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/Samba/sambaFunctions.sh

CONFIG_FILE="/mnt/SDCARD/App/Samba/config.json"

#Leaving for future use; network services should be able to run silently
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1 #run silently via cli arg?

toggle_mainui() {
  if flag_check "samba"; then
    display -t "Shutting down Samba..." -c dbcda7
    # Samba is running, so we'll shut it down
    sed -i 's|- On|- Off|' "$CONFIG_FILE"
    sed -i 's|user: root, pass: tina|Enable Samba for network file share|' "$CONFIG_FILE"
    kill -9 $(pgrep smbd)
    rm /mnt/SDCARD/App/Samba/runtime/run/smbd-smb.conf.pid
    flag_remove "samba"
  else
    # Samba is not running, so we'll start it
    display -t "Starting Samba..." -c dbcda7
    start_samba_process
    sed -i 's|Enable Samba for network file share|user: root, pass: tina|' "$CONFIG_FILE"
    flag_add "samba"
    display -t "Samba started
    User: root
    Password: tina" -c dbcda7 --okay
  fi
}

# Call the function
toggle_mainui
