#!/bin/sh

APP_DIR=/mnt/SDCARD/App/spruceRestore
UPGRADE_SCRIPTS_DIR=/mnt/SDCARD/App/spruceRestore/UpgradeScripts
BACKUP_DIR=/mnt/SDCARD/Saves/spruce

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

IMAGE_PATH="$APP_DIR/imgs/spruceRestore.png"
NOTFOUND_IMAGE_PATH="$APP_DIR/imgs/spruceRestoreNotfound.png"
SUCCESSFUL_IMAGE_PATH="$APP_DIR/imgs/spruceRestoreSuccess.png"
FAIL_IMAGE_PATH="$APP_DIR/imgs/spruceRestoreFailed.png"

log_message "----------Starting Restore script----------"
cores_online 4
show_image "$IMAGE_PATH"

#-----Main-----

# Set up logging
log_file="$BACKUP_DIR/spruceRestore.log"

log_message "Starting spruceRestore script..."
log_message "Looking for backup files..."

# Check if backups folder exists
if [ ! -d "$BACKUP_DIR/backups" ]; then
    log_message "Backup folder not found at $BACKUP_DIR/backups"
    show_image "$NOTFOUND_IMAGE_PATH"
    acknowledge
    exit 1
fi

# Look for spruceBackup 7z files
backup_files=$(find "$BACKUP_DIR/backups" -name "spruceBackup*.7z" | sort -r | tr '\n' ' ')

if [ -z "$backup_files" ]; then
    log_message "No spruceBackup 7z files found in $BACKUP_DIR/backups"
    show_image "$FAIL_IMAGE_PATH"
    acknowledge
    exit 1
fi

# Get the most recent backup file
most_recent_backup=$(echo $backup_files | cut -d ' ' -f 1)
log_message "Most recent backup file found: $(basename "$most_recent_backup")"

# Verify the integrity of the backup file
log_message "Verifying the integrity of the backup file..."
7zr t "$most_recent_backup" 2>> "$log_file"

if [ $? -ne 0 ]; then
    log_message "Backup file integrity check failed. The file may be corrupted."
    show_image "$FAIL_IMAGE_PATH"
    acknowledge
    exit 1
fi

# Define a list of flags to check and potentially restore
flags_to_process="expertRA"

# Function to process flags before restore
process_flags_before_restore() {
    for flag in $flags_to_process; do
        if flag_check "$flag"; then
            log_message "Removing $flag flag before restore"
            flag_remove "$flag"
            echo "$flag" >> "$backupdir/removed_flags.tmp"
        fi
    done
}

# Function to restore flags if restore fails
restore_flags_on_failure() {
    if [ -f "$backupdir/removed_flags.tmp" ]; then
        log_message "Restore failed. Restoring removed flags."
        while read -r flag; do
            log_message "Restoring $flag flag"
            flag_add "$flag"
        done < "$backupdir/removed_flags.tmp"
        rm "$backupdir/removed_flags.tmp"
    fi
}

# Process flags before restore
process_flags_before_restore

# Delete the originalProfile folder if it exists
if [ -d "/mnt/SDCARD/RetroArch/originalProfile" ]; then
    log_message "Deleting /mnt/SDCARD/RetroArch/originalProfile folder..."
    rm -rf /mnt/SDCARD/RetroArch/originalProfile
fi

# Actual restore process
log_message "Starting actual restore process..."
cd /
log_message "Current directory: $(pwd)"
log_message "Extracting backup file: $most_recent_backup"
7zr x -y "$most_recent_backup" 2>> "$log_file"

if [ $? -eq 0 ]; then
    log_message "Restore completed successfully"
    show_image "$SUCCESSFUL_IMAGE_PATH" 3
    rm -f "$backupdir/removed_flags.tmp"
else
    log_message "Error during restore process. Check $log_file for details."
    log_message "7zr exit code: $?"
    log_message "7zr output: $(7zr x -y "$most_recent_backup" 2>&1)"
    restore_flags_on_failure
    show_image "$FAIL_IMAGE_PATH"
    acknowledge
    exit 1
fi

# Check for expertRA flag and run retroExpert.sh if needed
if flag_check "expertRA"; then
    display -t "Detected RetroArch in backup was running in expert mode. Switching to expert mode now..." -c dbcda7 -d 2 -s 20
    log_message "expertRA flag found. Removing flag and running retroExpert.sh in silent mode."
    flag_remove "expertRA"
    if [ -f "/mnt/SDCARD/App/RetroExpert/retroExpert.sh" ]; then
        sh /mnt/SDCARD/App/RetroExpert/retroExpert.sh true
        log_message "retroExpert.sh executed in silent mode"
    else
        log_message "retroExpert.sh not found"
    fi
else
    log_message "expertRA flag not found. Skipping retroExpert.sh execution."
fi

# Check if Syncthing config folder exists and run launch script if it does
if [ -d "/mnt/SDCARD/App/Syncthing/config" ]; then
    log_message "Syncthing config folder found."
    if ! flag_check "syncthing"; then
        log_message "Syncthing injector not found in runtime. Running Syncthing launch script..."
        if [ -f "/mnt/SDCARD/App/Syncthing/launch.sh" ]; then
            sh /mnt/SDCARD/App/Syncthing/launch.sh
            if [ $? -eq 0 ]; then
                log_message "Syncthing launch script executed successfully"
            else
                log_message "Error executing Syncthing launch script"
            fi
        else
            log_message "Syncthing launch script not found"
        fi
    else
        log_message "Syncthing flag found. Skipping Syncthing launch."
    fi
else
    log_message "Syncthing config folder not found. Skipping Syncthing launch."
fi

#-----Upgrade-----
UPDATE_IMAGE_PATH="$APP_DIR/imgs/spruceUpdate.png"
UPDATE_SUCCESSFUL_IMAGE_PATH="$APP_DIR/imgs/spruceUpdateSuccess.png"
UPDATE_FAIL_IMAGE_PATH="$APP_DIR/imgs/spruceUpdateFailed.png"

log_message "Starting upgrade process..."
show_image "$UPDATE_IMAGE_PATH"

# Define the path for the .lastUpdate file
last_update_file="$APP_DIR/.lastUpdate"

# Read the current version from .lastUpdate file
if [ -f "$last_update_file" ]; then
    current_version=$(grep "spruce_version=" "$last_update_file" | cut -d'=' -f2)
else
    current_version="2.0.0"
fi

log_message "Current version: $current_version"

# Upgrade script locations
upgrade_scripts="
$UPGRADE_SCRIPTS_DIR/2.3.0.sh
"
#/mnt/SDCARD/App/spruceRestore/UpgradeScripts/2.3.1.sh

for script in $upgrade_scripts; do
    script_name=$(basename "$script")
    script_version=$(echo "$script_name" | cut -d'.' -f1-3)
    
    if [ "$current_version" = "0.0.0" ] || [ "$(printf '%s\n' "$current_version" "$script_version" | sort -V | head -n1)" = "$current_version" ]; then
        log_message "Starting upgrade script: $script_name"
        
        if [ -f "$script" ]; then
            log_message "Executing $script_name..."
            output=$(sh "$script" 2>&1)
            exit_status=$?
            
            log_message "Output from $script_name:"
            echo "$output" >> "$log_file"
            
            if [ $exit_status -eq 0 ]; then
                log_message "Successfully completed $script_name"
                echo "spruce_version=$script_version" > "$last_update_file"
                current_version=$script_version
            else
                log_message "Error running $script_name. Exit status: $exit_status"
                log_message "Error details: $output"
                show_image "$UPDATE_FAIL_IMAGE_PATH"
                acknowledge
                exit 1
            fi
        else
            log_message "Warning: Script $script_name not found. Skipping."
        fi
        
        log_message "Finished processing $script_name"
    else
        log_message "Skipping $script_name: Already at version $current_version or higher"
    fi
done

log_message "Upgrade process completed. Current version: $current_version"
show_image "$UPDATE_SUCCESSFUL_IMAGE_PATH" 3

log_message "----------Restore and Upgrade completed----------"
cores_online
