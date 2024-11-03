#!/bin/sh

# Add silent mode flag
silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1

APP_DIR=/mnt/SDCARD/App/spruceBackup
BACKUP_DIR=/mnt/SDCARD/Saves/spruce
FLAGS_DIR=/mnt/SDCARD/spruce/flags

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

log_verbose
ICON_PATH="/mnt/SDCARD/spruce/imgs/backup.png"

log_message "----------Running Backup script----------"
set_performance

# Modify display function to respect silent mode
display_message() {
    if [ "$silent_mode" -eq 0 ]; then
        display "$@"
    fi
}

display_message --icon "$ICON_PATH" -t "Backing up your spruce configs and files.........."
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Create the 'spruce' directory and 'backups' subdirectory if they don't exist
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
seven_z_filename=$(basename "$seven_z_file")
log_message "Backup file will be: $seven_z_file"

# Things being backed up:
# - Syncthing config
# - PICO-8 config
# - PPSSPP saves
# - Drastic saves
# - RetroArch main configs
# - RetroArch hotkeyprofile/nohotkeyprofile swap files
# - RetroArch core configs
# - RetroArch overlays (excluding specific folders)

# Define the folders to backup
folders="
/mnt/SDCARD/.config/ppsspp/PSP/SAVEDATA
/mnt/SDCARD/.config/ppsspp/PSP/PPSSPP_STATE
/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM
/mnt/SDCARD/App/spruceRestore/.lastUpdate
/mnt/SDCARD/Emu/PICO8/bin
/mnt/SDCARD/Emu/.emu_setup/overrides
/mnt/SDCARD/RetroArch/retroarch.cfg
/mnt/SDCARD/RetroArch/.retroarch/config
/mnt/SDCARD/RetroArch/.retroarch/overlay
/mnt/SDCARD/Emu/NDS/backup
/mnt/SDCARD/Emu/NDS/savestates
/mnt/SDCARD/spruce/bin/SSH/sshkeys
/mnt/SDCARD/spruce/bin/Syncthing/config
/mnt/SDCARD/spruce/settings/gs_list
/mnt/SDCARD/spruce/settings/spruce.cfg
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
    log_message "Error: Not enough free space. Required: 50 MB, Available: $((available_space / 1024 / 1024)) MB"
    display --icon "$ICON_PATH" -t "Backup failed, not enough space.
You need at least 50 MB free space to backup your files." --okay
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

log_message "Creating 7z archive"
7zr a -spf "$seven_z_file" @"$temp_file" -xr'!*/overlay/drkhrse/*' -xr'!*/overlay/Jeltron/*' -xr'!*/overlay/Onion-Spruce/*' 2>> "$log_file"
rm "$temp_file"

if [ $? -eq 0 ]; then
  log_message "Backup process completed successfully. Backup file: $seven_z_file"
  display_message --icon "$ICON_PATH" -t "Backup completed successfully! 
Backup file: $seven_z_filename
Located in /Saves/spruce/backups/" -d 4
else
  log_message "Error while creating backup."
  display --icon "$ICON_PATH" -t "Backup failed
Check '/Saves/spruce/spruceBackup.log' for more details" --okay
fi

log_message "Backup process finished running"
log_verbose

auto_regen_tmp_update