#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

start_pyui_message_writer
log_and_display_message "Attempting to fetch RetroAchievements authorization token from the server."

# get user and pass from spruce config
rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"

# insert username into ppsspp.ini
TMP_CFG="$(mktemp)"
PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
if sed -e "s|^AchievementsUserName.*|AchievementsUserName = \"$rac_user\"|" "$PSP_DIR/ppsspp.ini" > "$TMP_CFG"; then
    mv "$TMP_CFG" "$PSP_DIR/ppsspp.ini"
else
    rm -f "$TMP_CFG"
fi

# get auth token from RAC server
if spruce/scripts/emu/psp_rac_auth.sh "$rac_user" "$rac_pass"; then
    log_and_display_message "Authorization token for PPSSPP successfully retrieved!"
else
    log_and_display_message "Unable to get authorization from RAC server. Please check your credentials in spruce's RetroAchievements settings and try again."
fi

# allow user to read return message
sleep 3
stop_pyui_message_writer
