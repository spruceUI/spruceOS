#!/bin/sh

CONFIG_FILE="/mnt/SDCARD/App/SSH/config.json"
SSH_DIR="/mnt/SDCARD/App/SSH"
SSH_KEYS="$SSH_DIR/sshkeys"
DROPBEAR="$SSH_DIR/bin/dropbear"
DROPBEARKEY="$SSH_DIR/bin/dropbearkey"

toggle_mainui() {
  if grep -q "SSH - OFF" "$CONFIG_FILE"; then
    sed -i 's|SSH - OFF|SSH - ON|' "$CONFIG_FILE"
    sed -i 's|Enable SSH for Code Wizardry|user: root, pass: tina|' "$CONFIG_FILE"
    [ ! -d "$SSH_KEYS" ] && mkdir -p "$SSH_KEYS"
    [ ! -f "$SSH_KEYS/dropbear_rsa_host_key" ] && $DROPBEARKEY -t rsa -f "$SSH_KEYS/dropbear_rsa_host_key"
    [ ! -f "$SSH_KEYS/dropbear_dss_host_key" ] && $DROPBEARKEY -t dss -f "$SSH_KEYS/dropbear_dss_host_key"
    $DROPBEAR -r "$SSH_KEYS/dropbear_rsa_host_key" -r "$SSH_KEYS/dropbear_dss_host_key" &
  elif grep -q "SSH - ON" "$CONFIG_FILE"; then
    sed -i 's|SSH - ON|SSH - OFF|' "$CONFIG_FILE"
    sed -i 's|user: root, pass: tina|Enable SSH for Code Wizardry|' "$CONFIG_FILE"
    killall -9 dropbear
  fi
}

# Call the function
toggle_mainui
