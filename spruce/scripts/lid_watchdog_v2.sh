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

previous_state=1

launch_sleep_helper_once() {
    if [ -e /tmp/sleep_helper_started ]; then
        return 0
    fi
    /mnt/SDCARD/spruce/scripts/sleep_helper.sh
    while [ "$(device_lid_open)" = "0" ]; do
        sleep 0.5
    done
}

while true; do
    # Read current lid state (1 = open, 0 = closed)
    current_state=$(device_lid_open)

    # check lid sleep spruce setting
    lid_sleep_enabled="$(get_config_value '.menuOptions."System Settings".enableLidSensor.selected' "True")"

    case "$lid_sleep_enabled" in
        "True")
            # Detect lid close only
            if [ "$current_state" = "0" ] && [ "$previous_state" = "1" ]; then
                launch_sleep_helper_once
                current_state=$(device_lid_open)
            fi
            ;;
        "Only when unplugged")
            # Detect lid close and charging state
            if [ "$current_state" = "0" ] && [ "$previous_state" = "1" ] && [ "$(device_get_charging_status)" = "Discharging" ]; then
                launch_sleep_helper_once
                current_state=$(device_lid_open)
            fi
            ;;
        "False")
            # li'l extra sleep
            sleep 1
            ;;
    esac

    previous_state="$current_state"
    sleep 0.5
done
