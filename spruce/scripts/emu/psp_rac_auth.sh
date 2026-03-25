#!/bin/sh

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


# 2. Build the URL
# We encode the password manually to handle symbols like #, &, or +
ENC_USER=$(echo -n "$USER_VAL" | sed 's/%/%25/g; s/+/%2B/g; s/#/%23/g; s/&/%26/g; s/ /%20/g')
ENC_PASS=$(echo -n "$PASS_VAL" | sed 's/%/%25/g; s/+/%2B/g; s/#/%23/g; s/&/%26/g; s/ /%20/g')
URL="https://retroachievements.org/dorequest.php?r=login&u=$ENC_USER&p=$ENC_PASS"


# 3. Perform the API login with SSL bypass (-k or --no-check-certificate)
if command -v curl >/dev/null 2>&1; then
    # -s (silent), -L (follow redirects), -k (ignore SSL errors), -A (User Agent)
    RESPONSE=$(curl -sLk -A "$USER_AGENT" "$URL")
elif command -v wget >/dev/null 2>&1; then
    # -q (quiet), --no-check-certificate, -U (User Agent), -O - (output to stdout)
    RESPONSE=$(wget -q --no-check-certificate -U "$USER_AGENT" -O - "$URL")
else
    log_message "Error: Neither curl nor wget found."
    exit 1
fi


# 4. Extract the Token
# Handles both "Token":"XYZ" and "Token" : "XYZ"
TOKEN=$(echo "$RESPONSE" | sed -n 's/.*"Token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$TOKEN" ]; then
    log_message "RAC login failed."
    if [ -z "$RESPONSE" ]; then
        log_message "Reason: Empty response from server (Check your Wi-Fi or System Date/Time)." -v
    else
        log_message "Server Response: $RESPONSE" -v
    fi
    exit 1
fi


# 5. Save only the token
mkdir -p "$PSP_DIR"
echo -n "$TOKEN" > "$OUTPUT_FILE"

log_message "Success! Token generated and saved."
exit 0