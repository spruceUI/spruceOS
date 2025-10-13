#!/bin/sh


. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
log_message "*** lid_watchdog.sh: started" 

GPIO_PATH="/sys/devices/platform/hall-mh248/hallvalue"

get_system_volume() {
    config_file="/mnt/SDCARD/Saves/flip-system.json"

    if [ ! -f "$config_file" ]; then
        echo "0"
        return
    fi

    vol=$(jq -r '.vol // 0' "$config_file")
    echo $((vol * 5)) # Config is 0-20, amixer is 0-100
}

are_headphones_plugged_in() {
    gpio_path="/sys/class/gpio/gpio150/value"

    if [ ! -f "$gpio_path" ]; then
        return 1  # false (not plugged in)
    fi

    value=$(cat "$gpio_path" 2>/dev/null | tr -d '[:space:]')

    if [ "$value" = "0" ]; then
        return 0  # true (plugged in)
    else
        return 1  # false
    fi
}

_set_volume() {
    volume="$1"

    if [ "$volume" -eq 0 ]; then
        amixer sset "Playback Path" "OFF" >/dev/null 2>&1
        return
    fi

    echo "Setting volume to ${volume}"
    amixer cset "name='SPK Volume'" "$volume" >/dev/null 2>&1

    if are_headphones_plugged_in; then
        amixer sset "Playback Path" "HP" >/dev/null 2>&1
    else
        amixer sset "Playback Path" "SPK" >/dev/null 2>&1
    fi

    # Handle the "volume 5" quirk
    if [ "$volume" -eq 5 ]; then
        amixer cset "name='SPK Volume'" 10 >/dev/null 2>&1
        amixer cset "name='SPK Volume'" 0 >/dev/null 2>&1
    fi
}

fix_sleep_sound_bug() {
    config_volume=$(get_system_volume)
    echo "Restoring volume to ${config_volume}"

    amixer cset numid=2 0
    amixer cset numid=5 0

    if are_headphones_plugged_in; then
        amixer cset numid=2 3
    elif [ "$config_volume" -eq 0 ]; then
        amixer cset numid=2 0
    else
        amixer cset numid=2 2
    fi

    _set_volume "$config_volume"
    log_message "*** lid_watchdog.sh: Set volume to $config_volume"
}

# default to open
current_value=1
fix_sleep_sound_bug # Ensure it's correct on startup
while true; do
    VALUE=$(cat "$GPIO_PATH")
    if [ "$VALUE" -eq 0 ] && [ "$current_value" -eq 1 ]; then
        log_message "*** lid_watchdog.sh: lid closed - entering S3 sleep"
        current_value=0

        echo deep > /sys/power/mem_sleep
        echo mem > /sys/power/state
    elif [ "$VALUE" -eq 1 ] && [ "$current_value" -eq 0 ]; then
        current_value=1
        log_message "*** lid_watchdog.sh: lid opened"

        fix_sleep_sound_bug
    fi

    # TODO: switch to something that watches getevent, inotifywait doesn't work on GPIO and the hall sensor doesn't trigger interrupts
    # so we can't use gpiowait
    /mnt/SDCARD/spruce/bin64/inotifywait "$GPIO_PATH" -e modify -t 1 >/dev/null 2>&1
done

