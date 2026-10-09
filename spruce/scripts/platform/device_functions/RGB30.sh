#!/bin/sh
# Powkiddy RGB30 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The RGB30 ships without a rumble motor, but the pads for one are on the board
# (ArkOS wiki) and the singleadc-joypad driver already claims the PWM and
# advertises FF_RUMBLE, so the common evdev rumble works on a modded unit and
# costs a stock one nothing.


rgb_led() {
    [ -n "$6" ] && echo "$6" > "$LED_PATH/trigger"
    return 0
}

work_led_off() {
    echo 0 >${LED_PATH}/brightness
}

work_led_on() {
    echo 1 >${LED_PATH}/brightness
}