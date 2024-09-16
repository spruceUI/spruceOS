#!/bin/sh

appdir=/mnt/SDCARD/App/spruceBackup
backupdir=/mnt/SDCARD/Saves/spruce

. /mnt/SDCARD/.tmp_update/scripts/globalFunctions.sh

IMAGE_PATH="$appdir/imgs/spruceBackup.png"
UPDATE_IMAGE_PATH="$appdir/imgs/spruceBackupSuccess.png"
FAIL_IMAGE_PATH="$appdir/imgs/spruceBackupFailed.png"

log_message "----------Running Backup script----------"
show_image "$IMAGE_PATH"

# Create the 'spruce' directory and 'backups' subdirectory if they don't exist
mkdir -p "$backupdir/backups"

# Set up logging
log_file="$backupdir/spruceBackup.log"

log_message "Created or verified spruce and backups directories"

# Get current timestamp
timestamp=$(date +"%Y%m%d_%H%M%S")
log_message "Starting backup process with timestamp: $timestamp"

# Create .lastUpdate file with the current spruce version
upgradescriptsdir="/mnt/SDCARD/App/spruceRestore/UpgradeScripts"
current_version=$(ls "$upgradescriptsdir" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.sh$' | sort -V | tail -n 1 | sed 's/\.sh$//')
echo "spruce_version=$current_version" > "/mnt/SDCARD/App/spruceRestore/.lastUpdate"
log_message "Created .lastUpdate file with current version: $current_version"

# Replace zip_file with tar_file
tar_file="$backupdir/backups/spruceBackup_${timestamp}.tar.gz"
log_message "Backup file will be: $tar_file"


# Things being backed up:
# - Syncthing config
# - PICO-8 config
# - PPSSPP saves
# - Drastic saves
# - RetroArch main configs
# - RetroArch hotkeyprofile/nohotkeyprofile swap files
# - RetroArch core configs

# Define the folders to backup
folders="
/mnt/SDCARD/App/Syncthing/config
/mnt/SDCARD/App/PICO/bin
/mnt/SDCARD/.config/ppsspp/PSP/SAVEDATA
/mnt/SDCARD/.config/ppsspp/PSP/PPSSPP_STATE
/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM
/mnt/SDCARD/RetroArch/retroarch.cfg
/mnt/SDCARD/RetroArch/hotkeyprofile
/mnt/SDCARD/RetroArch/nohotkeyprofile
/mnt/SDCARD/RetroArch/.retroarch/config
/mnt/SDCARD/Emu/NDS/backup
/mnt/SDCARD/Emu/NDS/savestates
/mnt/SDCARD/App/SSH/sshkeys
/mnt/SDCARD/App/spruceRestore/.lastUpdate
"

log_message "Folders to backup: $folders"

# Replace the tar creation and loop with a single tar command
log_message "Starting backup process"
tar_command="tar -czf \"$tar_file\""

for item in $folders; do
  if [ -e "$item" ]; then
    log_message "Adding $item to backup list"
    tar_command="$tar_command -C / ${item#/}"
  else
    log_message "Warning: $item does not exist, skipping..."
  fi
done

log_message "Tar command: $tar_command"

# Execute the tar command
eval $tar_command 2>> "$log_file"

if [ $? -eq 0 ]; then
  log_message "Backup process completed successfully. Backup file: $tar_file"
  show_image "$UPDATE_IMAGE_PATH" 4
else
  log_message "Error while creating backup, check $log_file for more details"
  show_image "$FAIL_IMAGE_PATH" 4
fi

log_message "Backup process finished running"
