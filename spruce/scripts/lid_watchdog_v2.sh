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

# Tracks whether THIS lid close has already been acted on, which is not the
# same as the raw lid state. Latching the raw state meant a close that was
# rejected (charging, under "Only when unplugged") still counted as handled:
# unplugging later with the lid still shut could never sleep, because the
# open->closed edge never came round again until the lid was physically
# cycled. Cleared when the lid actually opens.
close_handled=0

launch_sleep_helper_once() {
    if [ -e /tmp/sleep_helper_started ]; then
        return 0
    fi
    /mnt/SDCARD/spruce/scripts/sleep_helper.sh
    while [ "$(device_lid_open)" = "0" ]; do
        sleep 0.5
    done
}

# The setting is read with jq, which is a fork of a real binary. This loop runs
# every 0.5 s for the life of the device, in menu and in game, so it only
# re-reads when spruce-config.json has actually changed: -nt is a shell builtin
# and costs nothing. The lid state is read with `read`, also a builtin, for the
# same reason. Measured on the Flip: this loop was two forks per half second.
CONFIG_FILE="/mnt/SDCARD/Saves/spruce/spruce-config.json"
CONFIG_STAMP="/tmp/lid_watchdog_config_stamp"
lid_sleep_enabled="True"
read_lid_setting() {
    lid_sleep_enabled="$(get_config_value '.menuOptions."System Settings".enableLidSensor.selected' "True")"
    touch "$CONFIG_STAMP"
}
read_lid_setting

while true; do
    # Read current lid state (1 = open, 0 = closed)
    current_state=$(device_lid_open)

    # check lid sleep spruce setting, only when the config file changed
    if [ "$CONFIG_FILE" -nt "$CONFIG_STAMP" ]; then
        read_lid_setting
    fi

    case "$lid_sleep_enabled" in
        "True")
            # Detect lid close only
            if [ "$current_state" = "0" ] && [ "$close_handled" = "0" ]; then
                close_handled=1
                launch_sleep_helper_once
                current_state=$(device_lid_open)
            fi
            ;;
        "Only when unplugged")
            # Detect lid close and charging state
            if [ "$current_state" = "0" ] && [ "$close_handled" = "0" ] && [ "$(device_get_charging_status)" = "Discharging" ]; then
                close_handled=1
                launch_sleep_helper_once
                current_state=$(device_lid_open)
            fi
            ;;
        "False")
            # li'l extra sleep
            sleep 1
            ;;
    esac

    # An open lid arms the next close, whether or not this one was acted on.
    [ "$current_state" = "1" ] && close_handled=0
    sleep 0.5
done
