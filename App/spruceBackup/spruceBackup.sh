#!/bin/sh

appdir=/mnt/SDCARD/App/spruceBackup
backupdir=/mnt/SDCARD/Saves/spruce

. /mnt/SDCARD/miyoo/scripts/helperFunctions.sh

SYNC_IMAGE="$appdir/imgs/spruceBackup.png"
SYNC_IMAGE_CONFIRM="$appdir/imgs/spruceBackupConfirm.png"

log_message "----------Running Backup script----------"
cores_online 4
display_text -i "$SYNC_IMAGE" -t "Backing up your spruce configs and files.........." -c dbcda7
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Create the 'spruce' directory and 'backups' subdirectory if they don't exist
mkdir -p "$backupdir/backups"

# Set up logging
log_file="$backupdir/spruceBackup.log"
log_message "Created or verified spruce and backups directories"

# Get current timestamp
timestamp=$(date +"%Y%m%d_%H%M%S")
log_message "Starting backup process with timestamp: $timestamp"

# Replace zip_file with 7z_file
seven_z_file="$backupdir/backups/spruceBackup_${timestamp}.7z"
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
/mnt/SDCARD/App/Syncthing/config
/mnt/SDCARD/App/PICO/bin
/mnt/SDCARD/.config/ppsspp/PSP/SAVEDATA
/mnt/SDCARD/.config/ppsspp/PSP/PPSSPP_STATE
/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM
/mnt/SDCARD/RetroArch/retroarch.cfg
/mnt/SDCARD/RetroArch/hotkeyprofile
/mnt/SDCARD/RetroArch/nohotkeyprofile
/mnt/SDCARD/RetroArch/.retroarch/config
/mnt/SDCARD/RetroArch/.retroarch/overlay
/mnt/SDCARD/Emu/NDS/backup
/mnt/SDCARD/Emu/NDS/savestates
/mnt/SDCARD/App/SSH/sshkeys
/mnt/SDCARD/App/spruceRestore/.lastUpdate
"

log_message "Folders to backup: $folders"

# Replace the tar creation and loop with a find command and tar
log_message "Starting backup process"
temp_file=$(mktemp)

# Check available space
required_space=$((50 * 1024 * 1024))  # 50 MB in bytes
available_space=$(df -B1 /mnt/SDCARD | awk 'NR==2 {print $4}')

if [ "$available_space" -lt "$required_space" ]; then
    log_message "Error: Not enough free space. Required: 50 MB, Available: $((available_space / 1024 / 1024)) MB"
    display_text -i "$SYNC_IMAGE_CONFIRM" -t "Backup failed, not enough space.
You need at least 50 MB free space to backup your files." -c dbcda7 --okay
    acknowledge
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
  display_text -i "$SYNC_IMAGE" -t "Backup completed successfully! 
Backup file: $seven_z_file
Located in /Saves/spruce/backups/" -c dbcda7 -d 4
else
  log_message "Error while creating backup."
  display_text -i "$SYNC_IMAGE_CONFIRM" -t "Backup failed
Check '/Saves/spruce/spruceBackup.log' for more details" -c dbcda7 --okay
  acknowledge
fi

log_message "Backup process finished running"
cores_online