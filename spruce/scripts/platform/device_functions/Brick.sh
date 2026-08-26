#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_a133p.sh"

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/trim-ui-brick-system.json"
}

init_gpio_a133p() {
    #PD11 pull high for VCC-5v
    echo 107 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio107/direction
    echo -n 1 > /sys/class/gpio/gpio107/value

    #rumble motor PH3
    echo 227 > /sys/class/gpio/export
    echo -n out > /sys/class/gpio/gpio227/direction
    echo -n 0 > /sys/class/gpio/gpio227/value

    #DIP Switch PH19
    echo 243 > /sys/class/gpio/export
    echo -n in > /sys/class/gpio/gpio243/direction
}

device_init() {
    device_init_a133p

    # Show the configured switch action's name in the Fn switch popup instead
    # of a generic ON/OFF. trimui_scened calls these popup scripts on every
    # flip, so overlay our Brick-only versions with a bind mount.
    FN_DIP_DIR="/usr/trimui/apps/fn_editor"

    # No risk if the old version gets called once. Don't need to wait to ensure its mounted before something
    # calls it
    mount --bind /mnt/SDCARD/spruce/brick/fn_dip/show_fn_dip_on_msg.sh "${FN_DIP_DIR}/show_fn_dip_on_msg.sh" &
    mount --bind /mnt/SDCARD/spruce/brick/fn_dip/show_fn_dip_off_msg.sh "${FN_DIP_DIR}/show_fn_dip_off_msg.sh" &

    run_trimui_osdd

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash
        chmod +x /bin/bash
    fi
    # Install the configured switch action into /usr/trimui/scene so the physical
    # switch follows Settings -> Button Settings -> Switch action. --now also
    # adopts, once, whatever action was already installed - on the Brick line that
    # is whatever the old fn_editor app last wrote, and it outlives the SD card.
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-switch-action --now
}

launch_startup_watchdogs() {
    # Common plus the shared TrimUI ones (volume sync); sets SYSTEM_CPU.
    launch_trimui_startup_watchdogs

    # Dispatch the Brick's Fn keys (spruce does not run the stock keymon that
    # would otherwise do this). Launched here so it lives alongside the other
    # durable watchdogs and survives the early-boot churn; pinned like them.
    # Brick-only: the Fn keys report as B_L3/B_R3, which are the stick clicks on
    # the Smart Pro.
    /mnt/SDCARD/spruce/brick/fnkey_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n fnkey_watchdog.sh &
}
