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
    if [ -d /proc/mi_modules ]; then
        # Listing one level down as well: the display settings need the exact
        # node name inside mi_disp, and the top level listing does not show it.
        for entry in /proc/mi_modules/*; do
            if [ -d "$entry" ]; then
                echo "  $entry/"
                for child in "$entry"/*; do
                    [ -e "$child" ] && echo "      $(basename "$child")"
                done
            else
                echo "  $entry"
            fi
        done
    else
        echo "  <missing>"
    fi

    echo
    echo "==== MI libraries (so we know the real names and where they live) ===="
    for d in /config/lib /customer/lib /usr/lib; do
        echo "  $d:"
        ls -1 "$d" 2>/dev/null | grep -i "^libmi" | sed 's/^/      /' || echo "      <none>"
    done

    echo
    echo "==== /dev mi nodes ===="
    ls -l /dev/mi_* 2>/dev/null || echo "  <none>"

    echo
    echo "==== probe: does opening the disp device create its proc node? ===="
    echo "before:"
    ls -1 /proc/mi_modules/mi_disp 2>/dev/null | sed 's/^/  /'
    if [ -e /dev/mi_disp ]; then
        # Just opening it, no ioctls. If the instance node appears afterwards then
        # mi_disp0 is missing only because nothing had the display open.
        ( exec 3<>/dev/mi_disp; sleep 1; exec 3>&- ) 2>/dev/null &
        probe_pid=$!
        sleep 0.3
        echo "during open:"
        ls -1 /proc/mi_modules/mi_disp 2>/dev/null | sed 's/^/  /'
        wait $probe_pid 2>/dev/null
        echo "after close:"
        ls -1 /proc/mi_modules/mi_disp 2>/dev/null | sed 's/^/  /'
    else
        echo "  /dev/mi_disp does not exist, cannot probe"
    fi

    echo
    echo "==== csc probe: what does the driver say about each command? ===="
    # colortemp is proven to reach the panel (a hard rgb cast showed up on screen)
    # but csc produces no output and no visible effect. Feed the node a few things
    # and read dmesg after each -- these drivers usually print usage on a command
    # they do not recognise, which tells us the real argument list.
    # Hold the device open ourselves for the duration. PyUI is stopped while a
    # task runs, so its handle is gone and the node with it -- we cannot rely on
    # anything else keeping it alive here.
    if [ -e /dev/mi_disp ]; then
        exec 3<>/dev/mi_disp
        if [ -e /proc/mi_modules/mi_disp/mi_disp0 ]; then
            for cmd in "help" "csc" "csc 0" "csc 0 3 50 50 50 0 0 0" "colortemp 0 0 0 0 128 128 128"; do
                dmesg -c >/dev/null 2>&1
                echo "  --- wrote: [$cmd]"
                echo "$cmd" > /proc/mi_modules/mi_disp/mi_disp0 2>&1
                sleep 0.2
                dmesg 2>/dev/null | tail -12 | sed 's/^/      /'
            done
            echo
            echo "  --- CscMatrix sweep: saturation forced to 0, 3s per matrix ---"
            echo "  --- watch the screen and note which step turns it grey ---"
            for m in 0 1 2 3 4 5 6 7; do
                echo "  step $m: csc 0 $m 50 50 50 0 0 0"
                echo "csc 0 $m 50 50 50 0 0 0" > /proc/mi_modules/mi_disp/mi_disp0 2>&1
                sleep 3
            done
            # put it back to something neutral before we let go
            echo "csc 0 0 50 50 50 50 0 0" > /proc/mi_modules/mi_disp/mi_disp0 2>&1
        else
            echo "  node did not appear after opening /dev/mi_disp"
        fi
        exec 3>&-
    else
        echo "  /dev/mi_disp does not exist"
    fi

    echo
    echo "==== what the display proc nodes report when read ===="
    echo "--- /proc/mi_modules/fb/mi_fb0 ---"
    head -c 4000 /proc/mi_modules/fb/mi_fb0 2>/dev/null || echo "  <unreadable>"
    echo
    echo "--- /proc/mi_modules/mi_disp/mi_disp0 (opening the device ourselves) ---"
    if [ -e /dev/mi_disp ]; then
        exec 4<>/dev/mi_disp
        head -c 4000 /proc/mi_modules/mi_disp/mi_disp0 2>/dev/null || echo "  <unreadable>"
        exec 4>&-
    else
        echo "  /dev/mi_disp does not exist"
    fi
    echo
    echo "--- /proc/mi_modules/mi_panel/* ---"
    for n in /proc/mi_modules/mi_panel/*; do
        case "$n" in *debug_*|*module_version*) continue ;; esac
        echo "  == $n"
        head -c 2000 "$n" 2>/dev/null
    done
    echo
    echo "--- /proc/mi_modules/common/pq_info ---"
    head -c 2000 /proc/mi_modules/common/pq_info 2>/dev/null || echo "  <unreadable>"

    echo
    echo "==== kernel log tail (may show rejected display commands) ===="
    dmesg 2>/dev/null | tail -40 || echo "  <unavailable>"

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
