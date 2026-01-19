#!/bin/sh

# Miyoo Flip and A30 Only
# TODO break apart into their respective classes as they aren't identical
# TODO Move needed variables from buttons_watchdog into here

get_contrast() {
    jq -r '.contrast' "$SYSTEM_JSON"
}

brightness_down() {
    # get current brightness and volume level
    BRIGHTNESS_LV=$(get_brightness_level)
    VOLUME_LV=$(get_volume_level)

    extended_brightness="$(get_config_value 'menuOptions."System Settings".extendedBrightness.selected' "False")"

    # setsharedmem binary on A30 does not accept a contrast argument (yet?)
    if [ "$PLATFORM" = "Flip" ]; then
        CONTRAST_LV=$(get_contrast)
    else
        unset CONTRAST_LV
    fi

    # if brightness value larger than zero
    if [ $BRIGHTNESS_LV -gt 0 ] ; then

        # update brightness level
        BRIGHTNESS_LV=$((BRIGHTNESS_LV-1))

        logger -p 15 -t "keymon[$$]" "brightness down"
        logger -p 15 -t "keymon[$$]" "setLCDBrightness $BRIGHTNESS_LV"
        
        # update screen brightness
        SYSTEM_BRIGHTNESS=$(map_brightness_to_system_value "$BRIGHTNESS_LV")
        echo "$SYSTEM_BRIGHTNESS" > "$DEVICE_BRIGHTNESS_PATH"

        # Update MainUI Config file
        sed -i "s/\"backlight\":\s*\([0-9]\|10\)/\"backlight\": $BRIGHTNESS_LV/" "$SYSTEM_JSON"

        logger -p 15 -t "keymon[$$]" "loadSystemState brightness changed 1 $BRIGHTNESS_LV"

    elif [ "$PLATFORM" = "Flip" ] && [ "$extended_brightness" = "True" ]; then   ### also, brightness is <= 0 from failing previous condition
        # if brightness is already at minimum, start tweaking contrast
        if [ "$CONTRAST_LV" -ge 2 ]; then # never let contrast go down to 0

            # update system.json
            CONTRAST_LV=$((CONTRAST_LV - 1))
            jq ".contrast = $CONTRAST_LV" "$SYSTEM_JSON" > /tmp/system.json && mv /tmp/system.json "$SYSTEM_JSON"

            # system.json uses 0-20 but modetest expects 0-100
            INTERNAL_CONTRAST=$((CONTRAST_LV * 5))
            modetest -M rockchip -a -w 179:contrast:$INTERNAL_CONTRAST
        fi
    fi

    # write volume + brightness [+ contrast] values to shared memory for MainUI to update its UI
    $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV" "$CONTRAST_LV"
}

brightness_up() {
    # get current brightness and volume levels
    BRIGHTNESS_LV=$(get_brightness_level)
    VOLUME_LV=$(get_volume_level)

    extended_brightness="$(get_config_value 'menuOptions."System Settings".extendedBrightness.selected' "False")"

    # setsharedmem binary on A30 does not accept a contrast argument (yet?)
    if [ "$PLATFORM" = "Flip" ]; then
        CONTRAST_LV=$(get_contrast)
    else
        unset CONTRAST_LV
    fi

    if [ "$BRIGHTNESS_LV" -eq 0 ] && [ "$PLATFORM" = "Flip" ] && [ "$extended_brightness" = "True" ] && [ "$CONTRAST_LV" -le 9 ]; then

        # update system.json
        CONTRAST_LV=$((CONTRAST_LV + 1))
        jq ".contrast = $CONTRAST_LV" "$SYSTEM_JSON" > /tmp/system.json && mv /tmp/system.json "$SYSTEM_JSON"

        # system.json uses 0-20 but modetest expects 0-100
        INTERNAL_CONTRAST=$((CONTRAST_LV * 5))
        modetest -M rockchip -a -w 179:contrast:$INTERNAL_CONTRAST

    elif [ $BRIGHTNESS_LV -lt 10 ] ; then  # if extended brightness setting not on, or contrast is at least 10

        # update brightness level
        BRIGHTNESS_LV=$((BRIGHTNESS_LV+1))

        logger -p 15 -t "keymon[$$]" "brightness up"
        logger -p 15 -t "keymon[$$]" "setLCDBrightness $BRIGHTNESS_LV"

        # update screen brightness
        SYSTEM_BRIGHTNESS=$(map_brightness_to_system_value "$BRIGHTNESS_LV")
        echo "$SYSTEM_BRIGHTNESS" > "$DEVICE_BRIGHTNESS_PATH"

        # Update MainUI Config file
        sed -i "s/\"backlight\":\s*\([0-9]\|10\)/\"backlight\": $BRIGHTNESS_LV/" "$SYSTEM_JSON"

        logger -p 15 -t "keymon[$$]" "loadSystemState brightness changed 1 $BRIGHTNESS_LV"
    
        # write both level value to shared memory for MainUI to update its UI

    fi

    $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV" "$CONTRAST_LV"
}
