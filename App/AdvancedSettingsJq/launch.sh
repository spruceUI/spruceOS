#!/bin/sh

LOG_FILE="/mnt/SDCARD/App/AdvancedSettings/advanced_settings.log"
SCRIPT_PATH="./advancedsettings.sh"

# Ensure the script is executable
chmod +x "$SCRIPT_PATH"

# Run the script in a subshell, redirecting output to the log file
(
    set -e  # Exit immediately if a command exits with a non-zero status
    "$SCRIPT_PATH"
) > "$LOG_FILE" 2>&1

# Check if the script exited with an error
if [ $? -ne 0 ]; then
    echo "Error: Advanced Settings script failed. Check $LOG_FILE for details." >&2
    exit 1
fi
