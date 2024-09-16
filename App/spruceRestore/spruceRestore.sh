#!/bin/sh

appdir=/mnt/SDCARD/App/spruceRestore
upgradescriptsdir=/mnt/SDCARD/App/spruceRestore/UpgradeScripts
backupdir=/mnt/SDCARD/Saves/spruce

. /mnt/SDCARD/.tmp_update/scripts/globalFunctions.sh

IMAGE_PATH="$appdir/imgs/spurceRestore.png"
UPDATE_IMAGE_PATH="$appdir/imgs/spruceRestoreSuccess.png"
FAIL_IMAGE_PATH="$appdir/imgs/spruceRestoreFailed.png"

log_message "----------Starting Restore script----------"
show_image "$IMAGE_PATH"

#-----Main-----

# Set up logging
log_file="$backupdir/spruceRestore.log"

log_message "Starting spruceRestore script..."
log_message "Looking for backup files..."

# Check if backups folder exists
if [ ! -d "$backupdir/backups" ]; then
    log_message "Backup folder not found at $backupdir/backups"
    show_image "$FAIL_IMAGE_PATH" 5
    exit 1
fi

# Look for spruceBackup tar.gz files
backup_files=$(find "$backupdir/backups" -name "spruceBackup*.tar.gz" | sort -r | tr '\n' ' ')

if [ -z "$backup_files" ]; then
    log_message "No spruceBackup tar.gz files found in $backupdir/backups"
    show_image "$FAIL_IMAGE_PATH" 5
    exit 1
fi

# Get the most recent backup file
most_recent_backup=$(echo $backup_files | cut -d ' ' -f 1)
log_message "Most recent backup file found: $(basename "$most_recent_backup")"

# Actual restore process
log_message "Starting actual restore process..."
cd /
tar -xzvf "$most_recent_backup" 2>> "$log_file"

if [ $? -eq 0 ]; then
    log_message "Restore completed successfully"
    show_image "$UPDATE_IMAGE_PATH" 5
else
    log_message "Error during restore process. Check $log_file for details."
    show_image "$FAIL_IMAGE_PATH" 5
    exit 1
fi