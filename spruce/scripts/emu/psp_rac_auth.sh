#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/raproxyFunctions.sh

# --- Configuration ---
PSP_DIR="/mnt/SDCARD/Saves/.config/ppsspp/PSP/SYSTEM"
OUTPUT_FILE="$PSP_DIR/ppsspp_retroachievements.dat"
USER_AGENT="PPSSPP"


# 1. Read credentials
USER_VAL="$1"
PASS_VAL="$2"

if [ -z "$USER_VAL" ] || [ -z "$PASS_VAL" ]; then
    log_message "Error: Missing RAC username or password."
    exit 1
fi
log_message "Logging in to RetroAchievements for $USER_VAL..." -v


TOKEN="$(rac_login_token "$USER_VAL" "$PASS_VAL" "$USER_AGENT")"
if [ -z "$TOKEN" ]; then
    log_message "RAC login failed."
    exit 1
fi


# 2. Save only the token
mkdir -p "$PSP_DIR"
echo -n "$TOKEN" > "$OUTPUT_FILE"

log_message "Success! Token generated and saved."
exit 0