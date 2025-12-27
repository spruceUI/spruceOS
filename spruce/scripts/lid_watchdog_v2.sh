#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Wait until hall sensor is ready
for i in $(seq 1 25); do
    device_lid_sensor_ready && break
    sleep 0.2
done

if ! device_lid_sensor_ready; then
    log_message "Lid sensor never became ready, lid watchdog disabled"
    exit 1
fi

log_message "Lid watchdog started, monitoring lid state"

# Read initial lid state
prev_state=$(device_lid_open)

while true; do
    # Read current lid state (1 = open, 0 = closed)
    current_state=$(device_lid_open)
    
    # Detect lid close event (transition from 1 to 0)
    if [ "$prev_state" = "1" ] && [ "$current_state" = "0" ]; then
        /mnt/SDCARD/spruce/scripts/sleep_helper.sh
    fi
    
    prev_state="$current_state"
    sleep 0.5
done
