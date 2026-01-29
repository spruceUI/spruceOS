#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

BACKUP_DIR=/mnt/SDCARD/Saves/spruce
ICON_PATH="/mnt/SDCARD/spruce/imgs/backup.png"
BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"

##### FUNCTIONS #####

backup_emu_settings() {
    mkdir -p "/mnt/SDCARD/Saves/spruce/emu_backups"
    for config in /mnt/SDCARD/Emu/*/config.json; do
        emu_name="$(basename "$(dirname "$config")")"
        cp -f "$config" "/mnt/SDCARD/Saves/spruce/emu_backups/$emu_name.json"
        log_message "Backed up config.json for $emu_name"
    done
}

backup_spruce_config() {
    mkdir -p "/mnt/SDCARD/Saves/spruce/backups"
    cp -f "/mnt/SDCARD/Saves/spruce/spruce-config.json"  "/mnt/SDCARD/Saves/spruce/backups/spruce-config.json"
    log_message "Backed up spruce-config.json"
}

backup_theme_configs() {
    local backup_root="/mnt/SDCARD/Saves/spruce/theme_backups"
    mkdir -p "$backup_root"

    for config in /mnt/SDCARD/Themes/*/config*json; do
        theme_dir="$(dirname "$config")"
        theme_name="$(basename "$theme_dir")"

        mkdir -p "$backup_root/$theme_name"
        cp -f "$config" "$backup_root/$theme_name/"
        log_message "Backed up $(basename "$config") for $theme_name"
    done
}


##### MAIN EXECUTION #####

log_message "----------Running Backup script----------"
start_pyui_message_writer

display_image_and_text "$ICON_PATH" 25 25 "Backing up your spruce configs and files! Please wait.........." 75

# twinkle them lights
rgb_led lrm12 breathe FFFF00 2100 "-1" mmc0

# Create Saves/spruce directory and 'backups' subdirectory if they don't exist
mkdir -p "$BACKUP_DIR/backups"

# Set up logging
log_file="$BACKUP_DIR/spruceBackup.log"
> "$log_file"  # Empty out or create the log file
log_message "Created or verified spruce and backups directories"

# Get current timestamp
timestamp=$(date +"%Y%m%d_%H%M%S")
log_message "Starting backup process with timestamp: $timestamp"

# Replace zip_file with 7z_file
seven_z_file="$BACKUP_DIR/backups/spruceBackup_${timestamp}.7z"
log_message "Backup file will be: $seven_z_file"

# Things being backed up:
# - Syncthing config
# - SSH keys
# - spruce emulator and system configs
# - modified theme configs
# - PICO-8 config and carts
# - Drastic saves and configs
# - Flycast standalone configs
# - RetroArch main configs
# - RetroArch core configs
# - RetroArch overlays (excluding specific folders)
# - Yabasanshiro standalone configs

# Define the folders to backup
folders="
/mnt/SDCARD/App/spruceRestore/.lastUpdate
/mnt/SDCARD/Emu/PICO8/.lexaloffle
/mnt/SDCARD/Emu/.emu_setup/n64_controller/Custom.rmp
/mnt/SDCARD/Emu/DC/config
/mnt/SDCARD/Emu/NDS/backup
/mnt/SDCARD/Emu/NDS/backup-32
/mnt/SDCARD/Emu/NDS/backup-64
/mnt/SDCARD/Emu/NDS/config/drastic-A30.cfg
/mnt/SDCARD/Emu/NDS/config/drastic-Brick.cfg
/mnt/SDCARD/Emu/NDS/config/drastic-SmartPro.cfg
/mnt/SDCARD/Emu/NDS/config/drastic-SmartProS.cfg
/mnt/SDCARD/Emu/NDS/config/drastic-Flip.cfg
/mnt/SDCARD/Emu/NDS/config/drastic-Pixel2.cfg
/mnt/SDCARD/Emu/NDS/savestates
/mnt/SDCARD/Emu/NDS/resources/settings_A30.json
/mnt/SDCARD/Emu/NDS/resources/settings_Flip.json
/mnt/SDCARD/Emu/NDS/resources/settings_Pixel2.json
/mnt/SDCARD/Emu/SATURN/.yabasanshiro
/mnt/SDCARD/RetroArch/.retroarch/config
/mnt/SDCARD/RetroArch/.retroarch/overlay
/mnt/SDCARD/RetroArch/.retroarch/shaders
/mnt/SDCARD/RetroArch/.retroarch/cheats
/mnt/SDCARD/RetroArch/platform/retroarch-A30.cfg
/mnt/SDCARD/RetroArch/platform/retroarch-Brick.cfg
/mnt/SDCARD/RetroArch/platform/retroarch-Flip.cfg
/mnt/SDCARD/RetroArch/platform/retroarch-SmartPro.cfg
/mnt/SDCARD/RetroArch/platform/retroarch-SmartProS.cfg
/mnt/SDCARD/RetroArch/platform/retroarch-Pixel2.cfg
/mnt/SDCARD/Saves/spruce/backups/spruce-config.json
/mnt/SDCARD/Saves/spruce/emu_backups
/mnt/SDCARD/Saves/spruce/theme_backups
/mnt/SDCARD/spruce/bin/Syncthing/config
/mnt/SDCARD/spruce/etc/ssh/keys
"

log_message "Folders to backup: $folders"

# Replace the tar creation and loop with a find command and tar
log_message "Starting backup process"
temp_file=$(mktemp)

# Check available space
required_space=$((50 * 1024 * 1024))  # 50 MB in bytes
available_space=$(df -k /mnt/SDCARD | awk 'NR==2 {print $4 * 1024}')

log_message "Required space: $required_space bytes"
log_message "Available space: $available_space bytes"

if [ "$available_space" -lt "$required_space" ]; then
    display_image_and_text "$BAD_IMG" 25 25 "Backup failed. Only $((available_space / 1024 / 1024)) MB available. You need at least 50 MB free space to backup your files." 75
    sleep 5
    exit 1
fi

log_message "Sufficient free space available. Proceeding with backup."

for item in $folders; do
    if [ -e "$item" ]; then
        log_message "Adding $item to backup list"
        echo "$item" >> "$temp_file"
    else
        log_message "Warning: $item does not exist, skipping..."
    fi
done

log_message "Backing up Emu config.json files"
backup_emu_settings

log_message "Backing up spruce-specific PyUI config"
backup_spruce_config

log_message "Backing up theme config files"
backup_theme_configs

log_message "Creating 7z archive"
7zr a -spf -mmt=2 "$seven_z_file" @"$temp_file" -xr'!*/overlay/drkhrse/*' -xr'!*/overlay/Jeltron/*' -xr'!*/overlay/Perfect/*' -xr'!*/overlay/Onion-Spruce/*' 2>> "$log_file"

if [ $? -eq 0 ]; then  
    display_image_and_text "$ICON_PATH" 25 25 "Backup completed successfully! Backups can be found in the Saves/spruce/backups/ directory." 75
elif [ $? -eq 1 ]; then # exit code 1 is with warnings, but still creates an archive.
    display_image_and_text "$ICON_PATH" 25 25 "Backup completed but with warnings. Check Saves/spruce/spruceBackup.log for more details. Backups can be found in the Saves/spruce/backups/ directory." 75
else                    # exit codes 2+ are various actual failures
    display_image_and_text "$BAD_IMG" 25 25 "Backup failed. Check Saves/spruce/spruceBackup.log for more details." 75
fi

rm "$temp_file"
sleep 5

# Clean up old backups, keeping only the 9 most recent
log_message "Cleaning up old backups..."
cd "$BACKUP_DIR/backups" || exit
ls -t spruceBackup_*.7z | tail -n +10 | while read -r old_backup; do
    log_message "Removing old backup: $old_backup"
    rm "$old_backup"
done

log_message "Backup process finished running"

auto_regen_tmp_update
