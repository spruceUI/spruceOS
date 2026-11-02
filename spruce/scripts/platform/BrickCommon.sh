#!/bin/sh

# The TrimUI Brick's own functions, over a vendor layer the board file sources first: Brick.sh (TrimUI's
# firmware, trimui_a133p.sh) and its variant BrickOakMOSS.sh (oakMOSS, oakMOSSCommon.sh).

get_config_path() {
    # Return the full path
    echo "/mnt/SDCARD/Saves/trim-ui-brick-system.json"
}

led_zone_settings() {
    echo "topBarLEDcolor m"
    echo "leftFnLEDcolor 1"
    echo "rightFnLEDcolor 2"
    echo "leftShoulderLEDcolor l"
    echo "rightShoulderLEDcolor r"
    echo "topBarLEDbrightness max_scale"
    echo "fnLEDbrightness max_scale_f1f2"
    echo "shoulderLEDbrightness max_scale_lr"
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

# Backlight 0 (raw 1) keeps a lit panel on but cannot light it after resume.
device_resume_backlight() {
    [ "$(jq -r '.backlight' "$SYSTEM_JSON")" = 0 ] || return 0
    "$DEVICE_PYTHON3_PATH" - <<'EOF'
import ctypes, fcntl, os, time
fd = os.open("/dev/disp", os.O_RDWR)
fcntl.ioctl(fd, 0x102, (ctypes.c_ulong * 4)(0, 25, 0, 0))
time.sleep(0.1)
fcntl.ioctl(fd, 0x102, (ctypes.c_ulong * 4)(0, 1, 0, 0))
os.close(fd)
EOF
}

device_init() {
    device_init_a133p

    if [ ! -x /bin/bash ]; then
        cp /mnt/SDCARD/spruce/smartpro/bin/bash /bin/bash
        chmod +x /bin/bash
    fi
    # Install the configured switch action into /usr/trimui/scene so the physical
    # switch follows Settings -> Button Settings -> Switch action. --now also
    # adopts, once, whatever action was already installed - on the Brick line that
    # is whatever the old fn_editor app last wrote, and it outlives the SD card.
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-switch-action --now

    # Same for the two Fn keys. fnkey_watchdog.sh runs whatever absolute path it
    # finds in /usr/trimui/fnkeys/f{1,2}key_launch, and until now nothing wrote
    # those files at all - the retired fn_editor wrote a JSON format the watchdog
    # never read, so the Fn keys silently did nothing.
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-fnkey-action f1 --now
    /mnt/SDCARD/spruce/scripts/FN_Button/apply-fnkey-action f2 --now
}

launch_startup_watchdogs() {
    # Common plus the shared TrimUI ones (volume sync); sets SYSTEM_CPU.
    launch_trimui_startup_watchdogs

    # Dispatch the Brick's Fn keys (spruce does not run the stock keymon that
    # would otherwise do this). Launched here so it lives alongside the other
    # durable watchdogs and survives the early-boot churn; pinned like them.
    # The watchdog takes its key codes from FN_KEY_LEFT / FN_KEY_RIGHT in the
    # platform config, because the Brick and the Brick Pro do not agree on them.
    stop_running_watchdog /mnt/SDCARD/spruce/brick/fnkey_watchdog.sh
    /mnt/SDCARD/spruce/brick/fnkey_watchdog.sh &
    pin_cpu "$SYSTEM_CPU" -n fnkey_watchdog.sh &
}
