#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/trimui_a133p.sh"

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/trim-ui-brick-pro-system.json"
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
    # The stock OSD daemon draws TrimUI's own popups - volume, brightness, the
    # Fn switch toast. PyUI draws its own, so running osdd just means two
    # different-looking notifications for the same event. Off unless asked for,
    # which is what the Smart Pro S has always done; this brings the rest of the
    # line into line with it.
    run_osd="$(get_config_value '.menuOptions."System Settings".trimuiOSD.selected' "False")"
    [ "$run_osd" = "True" ] && run_trimui_osdd

    mount --bind /mnt/SDCARD/spruce/brick/fn_dip/show_fn_dip_on_msg.sh "/usr/trimui/apps/fn_editor/show_fn_dip_on_msg.sh" &
    mount --bind /mnt/SDCARD/spruce/brick/fn_dip/show_fn_dip_off_msg.sh "/usr/trimui/apps/fn_editor/show_fn_dip_off_msg.sh" &

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash
        chmod +x /bin/bash
    fi
    # Install the configured switch action into /usr/trimui/scene so the physical
    # switch follows Settings -> Button Settings -> Switch action. --now also
    # adopts, once, whatever action was already installed - on the Brick line that
    # is whatever the old fn_editor app last wrote, and it outlives the SD card.
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-switch-action --now

    # Same for the two Fn keys. Nothing has ever written the launch files
    # fnkey_watchdog.sh reads, so these keys have never done anything here.
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-fnkey-action f1 --now
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-fnkey-action f2 --now
}

launch_startup_watchdogs() {
    # Common plus the shared TrimUI ones (volume sync); sets SYSTEM_CPU.
    launch_trimui_startup_watchdogs

    # Dispatch the Fn keys (spruce does not run the stock keymon that would
    # otherwise do this). The watchdog takes its key codes from FN_KEY_LEFT /
    # FN_KEY_RIGHT in the platform config, which on this device are KEY_F1/KEY_F2
    # rather than the Brick's 317/318 - those are real stick clicks here.
    stop_running_watchdog /mnt/SDCARD/spruce/brick/fnkey_watchdog.sh
    /mnt/SDCARD/spruce/brick/fnkey_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n fnkey_watchdog.sh &
}