#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

output7z=/mnt/SDCARD/bug_report.7z
device_state=/mnt/SDCARD/Saves/spruce/device_state.log

if [ -f $output7z ] ; then
    rm $output7z
fi

# Hardware state that the logs don't record. Landing it in Saves/spruce as a
# .log means the include patterns below already pick it up.
dump_node() {
    if [ -e "$1" ]; then
        printf '%s = %s\n' "$1" "$(cat "$1" 2>/dev/null || echo '<unreadable>')"
    else
        printf '%s = <missing>\n' "$1"
    fi
}

{
    echo "==== device ===="
    echo "date          : $(date)"
    echo "PLATFORM      : $PLATFORM"
    echo "DEVICE        : $DEVICE"
    if command -v get_miyoo_mini_variant >/dev/null 2>&1; then
        echo "mini variant  : $(get_miyoo_mini_variant 2>/dev/null)"
    fi
    echo "spruce version: $(cat /mnt/SDCARD/spruce/spruce 2>/dev/null)"

    echo
    echo "==== display / backlight nodes ===="
    echo "/sys/class/pwm/pwmchip0 :"
    ls -1 /sys/class/pwm/pwmchip0 2>/dev/null || echo "  <missing>"
    dump_node /sys/class/pwm/pwmchip0/pwm0/duty_cycle
    dump_node /sys/class/pwm/pwmchip0/pwm0/period
    dump_node /sys/class/pwm/pwmchip0/pwm0/enable
    dump_node /sys/devices/soc0/soc/1f003400.pwm/pwm/pwmchip0/pwm0/duty_cycle
    echo "/proc/mi_modules :"
    ls -1 /proc/mi_modules 2>/dev/null || echo "  <missing>"

    echo
    echo "==== config files the display settings write to ===="
    dump_node /appconfigs/system.json
    dump_node /mnt/SDCARD/Saves/mini-flip-system.json

    echo
    echo "==== processes that apply those settings ===="
    ps 2>/dev/null | grep -iE "keymon|audioserver|MainUI|main$" | grep -v grep || echo "  none running"
} > "$device_state" 2>&1

7zr a -spf2 "$output7z" \
            -i'!/mnt/SDCARD/Saves/*.json' \
            -i'!/mnt/SDCARD/Saves/cache/*.json' \
            -i'!/mnt/SDCARD/Saves/spruce/*.log' \
            -i'!/mnt/SDCARD/Saves/spruce/*.json' \
            -i'!/mnt/SDCARD/RetroArch/.retroarch/logs/*' \
            -i'!/mnt/SDCARD/spruce/spruce'

log_message "Debug: Logs and configs saved to ${output7z}"
