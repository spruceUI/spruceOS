#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

PLAYBACK_PATH="Playback Path"
PLAYBACK_PATH_SPK="SPK"
PLAYBACK_PATH_HP="HP"

# Initial value at boot, 0 unplugged, 1 plugged
case $(gpioget --numeric -c 2 22) in
	0)
		amixer -c0 sset "${PLAYBACK_PATH}" "${PLAYBACK_PATH_SPK}"
		PREV_VALUE=2
		;;
	1)
		amixer -c0 sset "${PLAYBACK_PATH}" "${PLAYBACK_PATH_HP}"
		PREV_VALUE=1
		;;
esac

# Monitoring value, 1 plugged, 2 unplugged
gpiomon --format="%e" -c 2 22 | while read line; do
    NEW_VALUE=$line

    if [ "$NEW_VALUE" != "$PREV_VALUE" ]; then
        case "$NEW_VALUE" in
            2)
                amixer -c0 sset "${PLAYBACK_PATH}" "${PLAYBACK_PATH_SPK}"
                ;;
            1)
                amixer -c0 sset "${PLAYBACK_PATH}" "${PLAYBACK_PATH_HP}"
                ;;
        esac

        VOLUME_LV=$(get_volume_level)
        set_volume "$(( VOLUME_LV ))"

        PREV_VALUE="$NEW_VALUE"
    fi
done
