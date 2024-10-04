#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/SSH/dropbearFunctions.sh

CONFIG_FILE="/mnt/SDCARD/App/SSH/config.json"
SSH_DIR="/mnt/SDCARD/App/SSH"
SSH_KEYS="$SSH_DIR/sshkeys"
DROPBEAR="$SSH_DIR/bin/dropbear"
DROPBEARKEY="$SSH_DIR/bin/dropbearkey"

#Leaving for future use; network services should be able to run silently
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1 #run silently via cli arg?

flag_exists(){
    if flag_check "dropbear"; then
        return 0
    else
        return 1
    fi
}

toggle_mainui() {
  if flag_exists; then
    display -t "Shutting down SSH..." -c dbcda7
    # Dropbear is running, so we'll shut it down
    sed -i 's|- On|- Off|' "$CONFIG_FILE"
    sed -i 's|user: root, pass: tina|Enable SSH for code wizardry|' "$CONFIG_FILE"
    killall -9 dropbear
    flag_remove "dropbear"
  else
    # Dropbear is not running, so we'll start it
    display -t "Starting SSH..." -c dbcda7
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    [ ! -f "$SSH_KEYS/dropbear_rsa_host_key" ] && $DROPBEARKEY -t rsa -f "$SSH_KEYS/dropbear_rsa_host_key"
    [ ! -f "$SSH_KEYS/dropbear_dss_host_key" ] && $DROPBEARKEY -t dss -f "$SSH_KEYS/dropbear_dss_host_key"
    start_dropbear_process
    sed -i 's|Enable SSH for code wizardry|user: root, pass: tina|' "$CONFIG_FILE"
    flag_add "dropbear"
    display -t "SSH started
    User: root
    Password: tina" -c dbcda7 --okay
  fi
}

# Call the function
toggle_mainui
