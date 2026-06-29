#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

VOLUME_LV=$(get_volume_level)
set_volume "$(( VOLUME_LV ))"

JACK_PATH=/sys/class/gpio/gpio86/value
PLAYBACK_PATH="Playback Path"
PLAYBACK_PATH_SPK="SPK"
PLAYBACK_PATH_HP="HP"

PREV_VALUE=$(cat $JACK_PATH)

while true; do
    NEW_VALUE=$(cat $JACK_PATH)

    if [ "$NEW_VALUE" != "$PREV_VALUE" ]; then
        log_message "*** headphones watchdog: change detected" -v

        case "$NEW_VALUE" in
            "0")
                amixer -c0 sset "${PLAYBACK_PATH}" "${PLAYBACK_PATH_SPK}"
                ;;
            "1")
                amixer -c0 sset "${PLAYBACK_PATH}" "${PLAYBACK_PATH_HP}"
                ;;
        esac

        VOLUME_LV=$(get_volume_level)
        set_volume "$(( VOLUME_LV ))"

        PREV_VALUE="$NEW_VALUE"
    fi

    sleep 1
done