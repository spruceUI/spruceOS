#!/bin/sh

# Add silent mode flag
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1

APP_DIR=/mnt/SDCARD/App/spruceRestore
UPGRADE_SCRIPTS_DIR=/mnt/SDCARD/App/spruceRestore/UpgradeScripts
BACKUP_DIR=/mnt/SDCARD/Saves/spruce
SYNCTHING_DIR=/mnt/SDCARD/spruce/bin/Syncthing

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/bin/Syncthing/syncthingFunctions.sh

ICON_PATH="/mnt/SDCARD/spruce/imgs/restore.png"

display_message() {
    if [ $silent_mode -eq 0 ]; then
        display "$@"
    fi
}

log_message "----------Starting Restore script----------"
cores_online 4
display_message --icon "$ICON_PATH" -t "Restoring from your most recent backup..."

#-----Main-----

# Set up logging
log_file="$BACKUP_DIR/spruceRestore.log"
>"$log_file" # Empty out or create the log file

log_message "Starting spruceRestore script..."
log_message "Looking for backup files..."

# Check if backups folder exists
if [ ! -d "$BACKUP_DIR/backups" ]; then
    log_message "Backup folder not found at $BACKUP_DIR/backups"
    display_message --icon "$ICON_PATH" -t "No backup found. Make sure you've ran the backup app or have a recent backup located in
    $BACKUP_DIR/backups" -o
    exit 1
fi

# Look for spruceBackup 7z files
backup_files=$(find "$BACKUP_DIR/backups" -name "spruceBackup*.7z" | sort -r | tr '\n' ' ')

if [ -z "$backup_files" ]; then
    log_message "No spruceBackup 7z files found in $BACKUP_DIR/backups"
    display_message --icon "$ICON_PATH" -t "Restore failed, check $log_file for details." -o
    exit 1
fi

# Get the most recent backup file
most_recent_backup=$(echo $backup_files | cut -d ' ' -f 1)
log_message "Most recent backup file found: $(basename "$most_recent_backup")"

# Verify the integrity of the backup file
log_message "Verifying the integrity of the backup file..."
7zr t "$most_recent_backup" 2>>"$log_file"

if [ $? -ne 0 ]; then
    log_message "Backup file integrity check failed. The file may be corrupted."
    display_message --icon "$ICON_PATH" -t "Restore failed, check $log_file for details." -o
    exit 1
fi


# Define the path for the .lastUpdate file
last_update_file="$APP_DIR/.lastUpdate"

compare_versions() {
    echo "$1 $2" | awk '{
        split($1, a, ".")
        split($2, b, ".")
        for (i = 1; i <= 3; i++) {
            if (a[i] < b[i]) {
                print "older"
                exit
            } else if (a[i] > b[i]) {
                print "newer"
                exit
            }
        }
        print "equal"
    }'
}

rm -f "$last_update_file"

# Actual restore process
log_message "Starting actual restore process..."
cd /
log_message "Current directory: $(pwd)"
log_message "Extracting backup file: $most_recent_backup"
7zr x -y "$most_recent_backup" 2>>"$log_file"

if [ $? -eq 0 ]; then
    log_message "Restore completed successfully"
    display_message --icon "$ICON_PATH" -t "Restore completed successfully!" -d 3
    rm -f "$backupdir/removed_flags.tmp"
else
    log_message "Error during restore process. Check $log_file for details."
    log_message "7zr exit code: $?"
    log_message "7zr output: $(7zr x -y "$most_recent_backup" 2>&1)"
    restore_flags_on_failure
    display_message --icon "$ICON_PATH" -t "Restore failed, check $log_file for details." -o
    exit 1
fi

# Move PICO files from legacy location to Emu folder if they exist
if [ -f "/mnt/SDCARD/App/PICO/bin/pico8.dat" ]; then
    mv "/mnt/SDCARD/App/PICO/bin/pico8.dat" "/mnt/SDCARD/Emu/PICO8/bin/pico8.dat"
fi
if [ -f "/mnt/SDCARD/App/PICO/bin/pico8_dyn" ]; then
    mv "/mnt/SDCARD/App/PICO/bin/pico8_dyn" "/mnt/SDCARD/Emu/PICO8/bin/pico8_dyn"
fi

# Check legacy PICO folder and delete it if it exists
if [ -d "/mnt/SDCARD/App/PICO/" ]; then
    log_message "PICO files moved. Deleting /mnt/SDCARD/App/PICO/ folder..."
    rm -rf "/mnt/SDCARD/App/PICO"
fi

# Check if legacy Syncthing config folder exists and run launch script if it does
if [ -d "/mnt/SDCARD/App/Syncthing/config" ]; then
    log_message "Syncthing legacy location config folder found."
    # Move it to the new location
    mv "/mnt/SDCARD/App/Syncthing/config" "$SYNCTHING_DIR/config"
    rm -rf "/mnt/SDCARD/App/Syncthing"
    setting_update "syncthing" "true"
fi

#-----Upgrade-----
UPDATE_IMAGE_PATH="$APP_DIR/imgs/spruceUpdate.png"
UPDATE_SUCCESSFUL_IMAGE_PATH="$APP_DIR/imgs/spruceUpdateSuccess.png"
UPDATE_FAIL_IMAGE_PATH="$APP_DIR/imgs/spruceUpdateFailed.png"

log_message "Starting upgrade process..."
display_message --icon "$ICON_PATH" -t "Applying upgrades to your system..."


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
$UPGRADE_SCRIPTS_DIR/3.0.0.sh
"
#/mnt/SDCARD/App/spruceRestore/UpgradeScripts/2.3.1.sh

for script in $upgrade_scripts; do
    script_name=$(basename "$script")
    script_version=$(echo "$script_name" | cut -d'.' -f1-3)

    # Replace the version comparison logic
    if [ "$(compare_versions "$current_version" "$script_version")" = "older" ]; then
        log_message "Starting upgrade script: $script_name"
        display_message --icon "$ICON_PATH" -t "Applying $script_name upgrades to your system..."

        if [ -f "$script" ]; then
            log_message "Executing $script_name..."
            output=$(sh "$script" 2>&1)
            exit_status=$?

            log_message "Output from $script_name:"
            echo "$output" >>"$log_file"

            if [ $exit_status -eq 0 ]; then
                log_message "Successfully completed $script_name"
                echo "spruce_version=$script_version" >"$last_update_file"
                current_version=$script_version
            else
                log_message "Error running $script_name. Exit status: $exit_status"
                log_message "Error details: $output"
                display_message --icon "$ICON_PATH" -t "Upgrade failed, check $log_file for details." -o
                exit 1
            fi
        else
            log_message "Warning: Script $script_name not found. Skipping."
        fi

        log_message "Finished processing $script_name"
    else
        log_message "Skipping $script_name: Current version $current_version is equal to or higher than $script_version"
    fi
done

log_message "Upgrade process completed. Current version: $current_version"
display_message --icon "$ICON_PATH" -t "Upgrades successful!" -d 2

log_message "----------Restore and Upgrade completed----------"
cores_online

auto_regen_tmp_update