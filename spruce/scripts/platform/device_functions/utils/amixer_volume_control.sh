#!/bin/sh

# Miyoo Flip and A30 Only

# TODO Move needed variables from buttons_watchdog into here


get_contrast() {
    jq -r '.contrast' "$SYSTEM_JSON"
}

save_volume_to_config_file() {
    VOLUME_LV=$1

    # Update MainUI Config file
    sed -i "s/\"vol\":\s*\([0-9]*\)/\"vol\": $VOLUME_LV/" "$SYSTEM_JSON"
}

amixer_volume_down() {
    # get current brightness and volume levels
    BRIGHTNESS_LV=$(get_brightness_level)
    VOLUME_LV=$(get_volume_level)

    # setsharedmem binary on A30 does not accept a contrast argument (yet?)
    if [ "$PLATFORM" = "Flip" ]; then
        CONTRAST_LV=$(get_contrast)
    else
        unset CONTRAST_LV
    fi

    # if value larger than zero
    if [ $VOLUME_LV -gt 0 ] ; then

        # update brightness level
        VOLUME_LV=$((VOLUME_LV-1))

        # update screen brightness
        SYSTEM_VOLUME=$(map_mainui_volume_to_system_value "$VOLUME_LV")
        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $SYSTEM_VOLUME > /dev/null

        if [ "$PLATFORM" = "A30" ] ; then
          logger -p 15 -t "keymon[$$]" "volume down $VOLUME_LV"
        elif [ "$PLATFORM" = "Flip" ] ; then
          # attempt to tell mainui what we're setting volume too- this is what keymon does, but it doesn't seem to be helping
          # get graphical notifications on volume change
          logger -p 15 -t "keymon[$$]" "volume down 0ms, sleeped -1"
          logger -p 15 -t "keymon[$$]" "set volume $VOLUME_LV, $SYSTEM_VOLUME"
        else
          logger -p 15 -t "keymon[$$]" "volume down $VOLUME_LV"
        fi

        # write both level value to shared memory for MainUI to update its UI
        $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV" "$CONTRAST_LV"
        save_volume_to_config_file "$VOLUME_LV"
    fi
}

amixer_volume_up() {
    # get current brightness and volume levels
    BRIGHTNESS_LV=$(get_brightness_level)
    VOLUME_LV=$(get_volume_level)

    # setsharedmem binary on A30 does not accept a contrast argument (yet?)
    if [ "$PLATFORM" = "Flip" ]; then
        CONTRAST_LV=$(get_contrast)
    else
        unset CONTRAST_LV
    fi
    
    # if value larger than zero
    if [ $VOLUME_LV -lt 20 ] ; then

        # update brightness level
        VOLUME_LV=$((VOLUME_LV+1))

        # update screen brightness
        SYSTEM_VOLUME=$(map_mainui_volume_to_system_value "$VOLUME_LV")
        amixer $SET_OR_CSET $NAME_QUALIFIER"$AMIXER_CONTROL" $SYSTEM_VOLUME > /dev/null

        if [ "$PLATFORM" = "A30" ] ; then
          logger -p 15 -t "keymon[$$]" "volume up $VOLUME_LV"
        elif [ "$PLATFORM" = "Flip" ] ; then
          logger -p 15 -t "keymon[$$]" "volume up 0ms"
          logger -p 15 -t "keymon[$$]" "set volume $VOLUME_LV, $SYSTEM_VOLUME"
        else
          logger -p 15 -t "keymon[$$]" "volume up $VOLUME_LV"
        fi

        # write both level value to shared memory for MainUI to update its UI
        $SETSHAREDMEM_PATH "$VOLUME_LV" "$BRIGHTNESS_LV" "$CONTRAST_LV"
        save_volume_to_config_file "$VOLUME_LV"
    fi
}


# Map the System Value to MainUI Volume level 
amixer_get_volume_level() {
  # TODO: does the a30 need the comma?
    value=$(amixer cget name="$AMIXER_CONTROL" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    case $value in
        $SYSTEM_VOLUME_0) echo 0 ;;
        $SYSTEM_VOLUME_1) echo 1 ;;
        $SYSTEM_VOLUME_2) echo 2 ;;
        $SYSTEM_VOLUME_3) echo 3 ;;
        $SYSTEM_VOLUME_4) echo 4 ;;
        $SYSTEM_VOLUME_5) echo 5 ;;
        $SYSTEM_VOLUME_6) echo 6 ;;
        $SYSTEM_VOLUME_7) echo 7 ;;
        $SYSTEM_VOLUME_8) echo 8 ;;
        $SYSTEM_VOLUME_9) echo 9 ;;
        $SYSTEM_VOLUME_10) echo 10 ;;
        $SYSTEM_VOLUME_11) echo 11 ;;
        $SYSTEM_VOLUME_12) echo 12 ;;
        $SYSTEM_VOLUME_13) echo 13 ;;
        $SYSTEM_VOLUME_14) echo 14 ;;
        $SYSTEM_VOLUME_15) echo 15 ;;
        $SYSTEM_VOLUME_16) echo 16 ;;
        $SYSTEM_VOLUME_17) echo 17 ;;
        $SYSTEM_VOLUME_18) echo 18 ;;
        $SYSTEM_VOLUME_19) echo 19 ;;
        $SYSTEM_VOLUME_20) echo 20 ;;
        *) echo 10 ;;
    esac
}

# Map the MainUI Volume level to System Value
map_mainui_volume_to_system_value() {
    case $1 in
        0) echo $SYSTEM_VOLUME_0 ;;
        1) echo $SYSTEM_VOLUME_1 ;;
        2) echo $SYSTEM_VOLUME_2 ;;
        3) echo $SYSTEM_VOLUME_3 ;;
        4) echo $SYSTEM_VOLUME_4 ;;
        5) echo $SYSTEM_VOLUME_5 ;;
        6) echo $SYSTEM_VOLUME_6 ;;
        7) echo $SYSTEM_VOLUME_7 ;;
        8) echo $SYSTEM_VOLUME_8 ;;
        9) echo $SYSTEM_VOLUME_9 ;;
        10) echo $SYSTEM_VOLUME_10 ;;
        11) echo $SYSTEM_VOLUME_11 ;;
        12) echo $SYSTEM_VOLUME_12 ;;
        13) echo $SYSTEM_VOLUME_13 ;;
        14) echo $SYSTEM_VOLUME_14 ;;
        15) echo $SYSTEM_VOLUME_15 ;;
        16) echo $SYSTEM_VOLUME_16 ;;
        17) echo $SYSTEM_VOLUME_17 ;;
        18) echo $SYSTEM_VOLUME_18 ;;
        19) echo $SYSTEM_VOLUME_19 ;;
        20) echo $SYSTEM_VOLUME_20 ;;
        *) ;;
    esac
}