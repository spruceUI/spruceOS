#!/bin/sh

appdir=/mnt/SDCARD/App/spruceRestore
upgradescriptsdir=/mnt/SDCARD/App/spruceRestore/UpgradeScripts
backupdir=/mnt/SDCARD/Saves/spruce

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

IMAGE_PATH="$appdir/imgs/spruceRestore.png"
NOTFOUND_IMAGE_PATH="$appdir/imgs/spruceRestoreNotfound.png"
SUCCESSFUL_IMAGE_PATH="$appdir/imgs/spruceRestoreSuccess.png"
FAIL_IMAGE_PATH="$appdir/imgs/spruceRestoreFailed.png"

check_injector() {
    if grep -q "#SYNCTHING INJECTOR" "/mnt/SDCARD/.tmp_update/runtime.sh"; then
        return 0
    else
        return 1
    fi
}

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
    show_image "$NOTFOUND_IMAGE_PATH"
    acknowledge
    exit 1
fi

# Look for spruceBackup tar.gz files
backup_files=$(find "$backupdir/backups" -name "spruceBackup*.tar.gz" | sort -r | tr '\n' ' ')

if [ -z "$backup_files" ]; then
    log_message "No spruceBackup tar.gz files found in $backupdir/backups"
    show_image "$FAIL_IMAGE_PATH"
    acknowledge
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
    show_image "$SUCCESSFUL_IMAGE_PATH" 3
else
    log_message "Error during restore process. Check $log_file for details."
    show_image "$FAIL_IMAGE_PATH"
    acknowledge
    exit 1
fi

# Check if Syncthing config folder exists and run launch script if it does
if [ -d "/mnt/SDCARD/App/Syncthing/config" ]; then
    log_message "Syncthing config folder found."
    if ! check_injector; then
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
        log_message "Syncthing injector found in runtime. Skipping Syncthing launch."
    fi
else
    log_message "Syncthing config folder not found. Skipping Syncthing launch."
fi

#-----Upgrade-----
UPDATE_IMAGE_PATH="$appdir/imgs/spruceUpdate.png"
UPDATE_SUCCESSFUL_IMAGE_PATH="$appdir/imgs/spruceUpdateSuccess.png"
UPDATE_FAIL_IMAGE_PATH="$appdir/imgs/spruceUpdateFailed.png"

log_message "Starting upgrade process..."
show_image "$UPDATE_IMAGE_PATH"

# Define the path for the .lastUpdate file
last_update_file="$appdir/.lastUpdate"

# Read the current version from .lastUpdate file
if [ -f "$last_update_file" ]; then
    current_version=$(grep "spruce_version=" "$last_update_file" | cut -d'=' -f2)
else
    current_version="0.0.0"
fi

log_message "Current version: $current_version"

# Upgrade script locations
upgrade_scripts="
/mnt/SDCARD/App/spruceRestore/UpgradeScripts/2.3.0.sh
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
