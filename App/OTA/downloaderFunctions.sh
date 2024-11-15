. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

download_progress() {
    local filepath="$1"
    local total_size_mb="$2"
    # Convert MB to bytes (1MB = 1048576 bytes)
    log_message "OTA: Total size: $total_size_mb MB"
    log_message "OTA: Filepath: $filepath"
    sleep 1
    
    while true; do
        # Check if file exists
        if [ ! -f "$filepath" ]; then
            log_message "File not found: $filepath"
            return 1
        fi
        
        # Get current size in bytes using POSIX-compliant ls -l
        CURRENT_SIZE=$(ls -ln "$filepath" 2>/dev/null | awk '{print $5}')
        log_message "OTA: Current size: $CURRENT_SIZE bytes"
        CURRENT_SIZE_MB=$(($CURRENT_SIZE / 1048576))
        log_message "OTA: Current size: $CURRENT_SIZE_MB MB"
        
        # Add check for CURRENT_SIZE
        if [ -z "$CURRENT_SIZE" ] || [ "$CURRENT_SIZE" = "0" ]; then
            log_message "OTA: Error: Could not get current file size for $filepath"
            sleep 1
            continue
        fi
        
        # Calculate percentage using simple MB comparison
        PERCENTAGE=$(( (CURRENT_SIZE_MB * 100) / total_size_mb ))
        
        log_message "OTA: Download progress: $PERCENTAGE% (Size: $CURRENT_SIZE_MB / $total_size_mb MB)"

        # Output progress
        display --icon "$IMAGE_PATH" -t "Downloading update... $PERCENTAGE%"
        
        # Exit if download is complete (>= 99%)
        if [ "$PERCENTAGE" -ge 99 ]; then
            log_message "Download complete"
            break
        fi
        
        sleep 5
    done
}