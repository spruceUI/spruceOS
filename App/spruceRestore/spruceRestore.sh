#!/bin/sh

# Add silent mode flag
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1

APP_DIR=/mnt/SDCARD/App/spruceRestore
UPGRADE_SCRIPTS_DIR=/mnt/SDCARD/App/spruceRestore/UpgradeScripts
BACKUP_DIR=/mnt/SDCARD/Saves/spruce
SYNCTHING_DIR=/mnt/SDCARD/spruce/bin/Syncthing

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/spruce/scripts/network/syncthingFunctions.sh

ICON_PATH="/mnt/SDCARD/spruce/imgs/restore.png"

display_message() {
    if [ $silent_mode -eq 0 ]; then
        display "$@"
    fi
}

restore_emu_settings() {
    if [ ! -d "/mnt/SDCARD/Saves/spruce/emu_backups" ]; then
        log_message "No emu_backups folder to restore settings from."
        return 1
    fi
    for configjson in /mnt/SDCARD/Saves/spruce/emu_backups/*.json; do

        emu_name="$(basename "$configjson" .json)"
        new_json="/mnt/SDCARD/Emu/$emu_name/config.json"

        [ -f "$new_json" ] || continue    # Skip if new config doesn’t exist

        if jq -e '.menuOptions.Emulator' "$new_json" >/dev/null; then
            selected_core="$(jq -r '.menuOptions.Emulator.selected' "$configjson")"
            overrides="$(jq '.menuOptions.Emulator.overrides' "$configjson")"
            [ "$overrides" = "null" ] && overrides='{}'
            log_message "$emu_name: selected core: $selected_core"
            log_message "$emu_name: overrides section: $overrides"
            tmpfile="$(mktemp)"
            jq \
                --arg selected "$selected_core" \
                --argjson overrides "$overrides" \
                '.menuOptions.Emulator.selected = $selected
                | .menuOptions.Emulator.overrides = $overrides' \
                "$new_json" > "$tmpfile" && mv -f "$tmpfile" "$new_json"
        fi
    done
}

log_message "----------Starting Restore script----------"
# set_performance
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

kill_network_services() {
    killall -9 dropbear
    #killall -9 smbd
    #killall -9 sftpgo
    killall -9 syncthing
}

kill_network_services
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
    current_version=$(grep "spruce_version=" "$last_update_file" | cut -d'=' -f2 | tr -d '\r\n')
else
    current_version="2.0.0"
fi

log_message "Current version: $current_version"

# List the contents of the directory for debugging
log_message "Contents of $UPGRADE_SCRIPTS_DIR: $(ls -l "$UPGRADE_SCRIPTS_DIR")"

# Use cd and a direct for loop instead of find
cd "$UPGRADE_SCRIPTS_DIR" || exit 1

# Before the upgrade loop, add check for developer/tester mode
is_developer_mode=$(flag_check "developer_mode" && echo "true" || echo "false")
is_tester_mode=$(flag_check "tester_mode" && echo "true" || echo "false")
allow_same_version=0

if [ "$is_developer_mode" = "true" ] || [ "$is_tester_mode" = "true" ]; then
    allow_same_version=1
    log_message "Dev/Tester mode detected, allowing same version upgrades"
fi

# Modify the version comparison logic in the upgrade loop
for script in *.sh; do
    [ -f "$script" ] || continue  # Skip if no .sh files found
    
    script_name="$script"
    script_version=$(echo "$script_name" | cut -d'.' -f1-3)

    version_compare=$(compare_versions "$current_version" "$script_version")
    # Run if version is older OR if same version and in developer/tester mode
    if [ "$version_compare" = "older" ] || ([ "$version_compare" = "equal" ] && [ $allow_same_version -eq 1 ]); then
        log_message "Starting upgrade script: $script_name"
        display_message --icon "$ICON_PATH" -t "Applying $script_name upgrades to your system..."

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
            cd - >/dev/null
            exit 1
        fi

        log_message "Finished processing $script_name"
    else
        log_message "Skipping $script_name: Current version $current_version is equal to or higher than $script_version"
    fi
done
cd - >/dev/null

log_message "Upgrade process completed. Current version: $current_version"
display_message --icon "$ICON_PATH" -t "Upgrades successful!" -d 2


# Apply settings

log_message "Restoring emulator settings"
restore_emu_settings

log_message "Applying idlemon setting"
sh /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh reapply

log_message "----------Restore and Upgrade completed----------"

auto_regen_tmp_update

# Copy spruce.cfg to www folder so the landing page can read it.
cp "/mnt/SDCARD/spruce/settings/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"

exit 0
