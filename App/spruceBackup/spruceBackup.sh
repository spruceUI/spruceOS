#!/bin/sh

APP_DIR=/mnt/SDCARD/App/spruceBackup
BACKUP_DIR=/mnt/SDCARD/Saves/spruce
FLAGS_DIR=/mnt/SDCARD/spruce/flags

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SYNC_IMAGE="$APP_DIR/imgs/spruceBackup.png"
SYNC_IMAGE_CONFIRM="$APP_DIR/imgs/spruceBackupConfirm.png"

log_message "----------Running Backup script----------"
cores_online 4
display -i "$SYNC_IMAGE" -t "Backing up your spruce configs and files.........." -c dbcda7
echo mmc0 >/sys/devices/platform/sunxi-led/leds/led1/trigger &

# Create the 'spruce' directory and 'backups' subdirectory if they don't exist
mkdir -p "$BACKUP_DIR/backups"

# Set up logging
log_file="$BACKUP_DIR/spruceBackup.log"
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
/mnt/SDCARD/App/Syncthing/config
/mnt/SDCARD/App/PICO/bin
/mnt/SDCARD/.config/ppsspp/PSP/SAVEDATA
/mnt/SDCARD/.config/ppsspp/PSP/PPSSPP_STATE
/mnt/SDCARD/.config/ppsspp/PSP/SYSTEM
/mnt/SDCARD/RetroArch/retroarch.cfg
/mnt/SDCARD/RetroArch/hotkeyprofile
/mnt/SDCARD/RetroArch/nohotkeyprofile
/mnt/SDCARD/RetroArch/originalProfile
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
    display -i "$SYNC_IMAGE_CONFIRM" -t "Backup failed, not enough space.
You need at least 50 MB free space to backup your files." -c dbcda7 --okay
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

# Add the expertRA.lock file separately
if [ -e "$FLAGS_DIR/expertRA.lock" ]; then
  log_message "Adding $FLAGS_DIR/expertRA.lock to backup list"
  echo "$FLAGS_DIR/expertRA.lock" >> "$temp_file"
else
  log_message "Warning: $FLAGS_DIR/expertRA.lock does not exist, skipping..."
fi

log_message "Creating 7z archive"
7zr a -spf "$seven_z_file" @"$temp_file" -xr'!*/overlay/drkhrse/*' -xr'!*/overlay/Jeltron/*' -xr'!*/overlay/Onion-Spruce/*' 2>> "$log_file"
rm "$temp_file"

if [ $? -eq 0 ]; then
  log_message "Backup process completed successfully. Backup file: $seven_z_file"
  display -i "$SYNC_IMAGE" -t "Backup completed successfully! 
Backup file: $seven_z_filename
Located in /Saves/spruce/backups/" -c dbcda7 -d 4 -s 24
else
  log_message "Error while creating backup."
  display -i "$SYNC_IMAGE_CONFIRM" -t "Backup failed
Check '/Saves/spruce/spruceBackup.log' for more details" -c dbcda7 --okay
fi

log_message "Backup process finished running"
cores_online