. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR=/mnt/SDCARD/App/spruceRestore
BACKUP_DIR=/mnt/SDCARD/Saves/spruce
CONFIG=$APP_DIR/config.json

# Check if the restore app is hidden
if grep -q '"#label"' "$CONFIG"; then
    log_message "Restore app is hidden"
    # Check if the "backups" folder exists within BACKUP_DIR
    if [ ! -d "$BACKUP_DIR/backups" ]; then
        log_message "Backups folder does not exist: $BACKUP_DIR/backups"
        exit 1
    fi

    # Add debugging information
    log_message "Listing contents of $BACKUP_DIR/backups:"
    ls -l "$BACKUP_DIR/backups"

    # Check if there are any 7z files in the "backups" folder
    backup_files=$(find "$BACKUP_DIR/backups" -name "spruceBackup*.7z" | sort -r | tr '\n' ' ')
    if [ -z "$backup_files" ]; then
        log_message "No spruceBackup 7z files found in $BACKUP_DIR/backups"
        exit 1
    else
        log_message "7z files found in backups folder"
    fi

    # Change "#label" to "label" in the config file
    sed -i 's|"#label"|"label"|' "$CONFIG"
    log_message "Restore app is now visible"
else
    log_message "Restore app is already visible"
fi
