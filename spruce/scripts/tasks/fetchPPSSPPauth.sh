#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

start_pyui_message_writer
log_and_display_message "Attempting to fetch RetroAchievements authorization token from the server."

rac_user="$(get_config_value '.menuOptions."RetroAchievements Settings".username.selected' "")"
rac_pass="$(get_config_value '.menuOptions."RetroAchievements Settings".password.selected' "")"

if spruce/scripts/emu/psp_rac_auth.sh "$rac_user" "$rac_pass"; then
    log_and_display_message "Authorization token for PPSSPP successfully retrieved!"
else
    log_and_display_message "Unable to get authorization from RAC server. Please check your credentials in spruce's RetroAchievements settings and try again."
fi
sleep 3
stop_pyui_message_writer
