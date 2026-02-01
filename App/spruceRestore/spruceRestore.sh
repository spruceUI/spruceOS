#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

APP_DIR=/mnt/SDCARD/App/spruceRestore
UPGRADE_SCRIPTS_DIR=/mnt/SDCARD/App/spruceRestore/UpgradeScripts
BACKUP_DIR=/mnt/SDCARD/Saves/spruce
ICON_PATH="/mnt/SDCARD/spruce/imgs/restore.png"
BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"
python_path="$(get_python_path)"
##### FUNCTIONS #####
# Set up logging
log_file="$BACKUP_DIR/spruceRestore.log"
>"$log_file" # Empty out or create the log file

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
    ssh_service=$(get_ssh_service_name)

    killall -9 $ssh_service
    #killall -9 smbd
    #killall -9 sftpgo
    killall -9 syncthing
}

restore_emu_settings() {
    backup_dir="/mnt/SDCARD/Saves/spruce/emu_backups"
    emu_dir="/mnt/SDCARD/Emu"
    menu_fields="Emulator Governor Emulator_A30 Emulator_Flip Emulator_Brick Emulator_64 Stretch controlMode"

    if [ ! -d "$backup_dir" ]; then
        log_message "No emu_backups folder to restore settings from."
        return 1
    fi

    for configjson in "$backup_dir"/*.json; do
        [ -f "$configjson" ] || continue
        emu_name="$(basename "$configjson" .json)"
        new_json="$emu_dir/$emu_name/config.json"

        [ -f "$new_json" ] || continue  # Skip if emulator no longer exists

        log_message "Merging $configjson → $new_json"
        "$python_path" /mnt/SDCARD/App/spruceRestore/merge_configs.py \
                "$configjson" \
                "$new_json" \
                >> "$log_file" 2>&1
    done
}

restore_spruce_config() {
    local old_config="/mnt/SDCARD/Saves/spruce/backups/spruce-config.json"
    local new_config="/mnt/SDCARD/Saves/spruce/spruce-config.json"
    
    [ -f "$old_config" ] || { log_message "Old config not found: $old_config"; return 1; }
    [ -f "$new_config" ] || { log_message "New config not found: $new_config"; return 1; }

    log_message "Merging $old_config → $new_config"
    "$python_path" /mnt/SDCARD/App/spruceRestore/merge_configs.py \
                "$old_config" \
                "$new_config" \
                >> "$log_file" 2>&1

    log_message "Config restore complete."
}

restore_theme_configs() {
    local backup_root="/mnt/SDCARD/Saves/spruce/theme_backups"
    [ -d "$backup_root" ] || log_message "No theme configs to restore." && return 1

    for theme_name in "$backup_root"/*; do
        [ -d "$theme_name" ] || continue

        base_theme="$(basename "$theme_name")"
        dest_dir="/mnt/SDCARD/Themes/$base_theme"

        if [ -d "$dest_dir" ]; then
            cp -f "$theme_name"/config*json "$dest_dir"/
            log_message "Restored configs for theme $base_theme"
        else
            log_message "Skipping restore for missing theme: $base_theme"
        fi
    done
}

##### MAIN EXECUTION #####

log_message "----------Starting Restore script----------"
start_pyui_message_writer

display_image_and_text "$ICON_PATH" 25 25 "Restoring from your most recent backup..." 75

# twinkle them lights
rgb_led lrm12 breathe 00FF00 1900 "-1" mmc0

log_message "Looking for backup files..."

# Check if backups folder exists
if [ ! -d "$BACKUP_DIR/backups" ]; then
    display_image_and_text "$BAD_IMG" 25 25 "No backup found. Make sure you've ran the backup app or have a recent backup located in $BACKUP_DIR/backups" 75
    sleep 5
    exit 1
fi

# Look for spruceBackup 7z files
backup_files=$(find "$BACKUP_DIR/backups" -name "spruceBackup*.7z" | sort -r | tr '\n' ' ')

if [ -z "$backup_files" ]; then
    display_image_and_text "$BAD_IMG" 25 25 "No spruceBackup 7z files found in $BACKUP_DIR/backups. Unable to restore." 75
    sleep 5
    exit 1
fi

# Get the most recent backup file
most_recent_backup=$(echo $backup_files | cut -d ' ' -f 1)
log_message "Most recent backup file found: $(basename "$most_recent_backup")"

# Verify the integrity of the backup file
log_message "Verifying the integrity of the backup file..."
7zr t "$most_recent_backup" 2>>"$log_file"

if [ $? -ne 0 ]; then
    display_image_and_text "$BAD_IMG" 25 25 "Backup file integrity check failed. The file may be corrupted." 75
    sleep 5
    exit 1
fi

# Define the path for the .lastUpdate file
last_update_file="$APP_DIR/.lastUpdate"

kill_network_services
rm -f "$last_update_file" # wipe this so we can restore it and see what version the backup was made on

# Actual restore process
log_message "Starting actual restore process..."
cd /
log_message "Current directory: $(pwd)"
log_message "Extracting backup file: $most_recent_backup"
7zr x -y "$most_recent_backup" 2>>"$log_file"

if [ $? -eq 0 ]; then
    display_image_and_text "$ICON_PATH" 25 25 "Restore completed successfully!" 75
    sleep 5
    rm -f "$backupdir/removed_flags.tmp"
else
    log_message "7zr exit code: $?"
    log_message "7zr output: $(7zr x -y "$most_recent_backup" 2>&1)"
    display_image_and_text "$ICON_PATH" 25 25 "Restore failed! Check $log_file for details." 75
    sleep 5
    exit 1
fi


#-----Upgrade-----
UPDATE_IMAGE_PATH="$APP_DIR/imgs/spruceUpdate.png"
UPDATE_SUCCESSFUL_IMAGE_PATH="$APP_DIR/imgs/spruceUpdateSuccess.png"
UPDATE_FAIL_IMAGE_PATH="$APP_DIR/imgs/spruceUpdateFailed.png"

log_message "Starting upgrade process..."
display_image_and_text "$ICON_PATH" 25 25  "Applying upgrades to your system..." 75
sleep 2
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
    log_message "Dev/Tester mode detected; allowing same version upgrades"
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
        display_image_and_text "$ICON_PATH" 25 25 "Applying $script_name upgrades to your system..." 75

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
            display_image_and_text "$ICON_PATH" 25 25 "Migration failed; check $log_file for details." 75

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
display_image_and_text "$ICON_PATH" 25 25 "Upgrades successful!" 75
sleep 2


# Apply settings

display_image_and_text "$ICON_PATH" 25 25 "Restoring emulator, theme, and system settings..." 75

log_message "Restoring emulator settings"
restore_emu_settings

log_message "Restoring compatible values from previous spruce-config.json"
restore_spruce_config

log_message "Restoring theme customizations"
restore_theme_configs

log_message "Applying idlemon setting"
sh /mnt/SDCARD/spruce/scripts/applySetting/idlemon_mm.sh reapply

log_message "----------Restore and Upgrade completed----------"

auto_regen_tmp_update

# Copy spruce.cfg to www folder so the landing page can read it.
# cp "/mnt/SDCARD/spruce/settings/spruce.cfg" "/mnt/SDCARD/spruce/www/sprucecfg.bak"

exit 0
