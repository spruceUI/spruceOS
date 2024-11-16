. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

download_progress() {
    local filepath="$1"
    local total_size_mb="$2"
    # Add start time tracking
    START_TIME=$(date +%s)
    local prev_size=0
    
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
        CURRENT_SIZE_MB=$(($CURRENT_SIZE / 1048576))
        
        # Calculate ETA
        CURRENT_TIME=$(date +%s)
        ELAPSED_SECONDS=$((CURRENT_TIME - START_TIME))
        
        if [ "$ELAPSED_SECONDS" -gt 0 ] && [ "$CURRENT_SIZE" -gt "$prev_size" ]; then
            # Calculate speed in MB/s
            SPEED_MB=$(( (CURRENT_SIZE_MB * 100) / (ELAPSED_SECONDS * 100) ))
            # Calculate remaining MB
            REMAINING_MB=$((total_size_mb - CURRENT_SIZE_MB))
            # Calculate remaining seconds
            if [ "$SPEED_MB" -gt 0 ]; then
                REMAINING_SECONDS=$((REMAINING_MB / SPEED_MB))
                # Convert to minutes and seconds
                REMAINING_MIN=$((REMAINING_SECONDS / 60))
                REMAINING_SEC=$((REMAINING_SECONDS % 60))
                ETA_MSG="Time remaining: ${REMAINING_MIN}m ${REMAINING_SEC}s"
            else
                ETA_MSG="Time remaining: calculating..."
            fi
        else
            ETA_MSG="Time remaining: calculating..."
        fi
        
        PERCENTAGE=$(( (CURRENT_SIZE_MB * 100) / total_size_mb ))
        
        log_message "OTA: Download progress: $PERCENTAGE% (Size: $CURRENT_SIZE_MB / $total_size_mb MB)$ETA_MSG"
        
        # Calculate filled and empty segments of progress bar (20 chars total)
        FILLED_CHARS=$((PERCENTAGE / 5))
        EMPTY_CHARS=$((20 - FILLED_CHARS))
        PROGRESS_BAR=""
        
        # Build progress bar string
        i=0
        while [ $i -lt $FILLED_CHARS ]; do
            PROGRESS_BAR="${PROGRESS_BAR}="
            i=$((i + 1))
        done
        while [ $i -lt 20 ]; do
            PROGRESS_BAR="${PROGRESS_BAR}   "
            i=$((i + 1))
        done

        # Update display with ETA and progress bar
        display --icon "$IMAGE_PATH" -t "Downloading update... $PERCENTAGE%
$ETA_MSG
[${PROGRESS_BAR}]"
        
        # Update previous size for next iteration
        prev_size=$CURRENT_SIZE
        
        # Exit if download is complete (>= 99%)
        if [ "$PERCENTAGE" -ge 99 ]; then
            log_message "Download complete"
            break
        fi
        
        sleep 5
    done
}