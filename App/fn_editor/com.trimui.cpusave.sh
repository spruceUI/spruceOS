#!/bin/sh
echo "============= scene CPUFREQ ============"

THERMAL_PROFILE_PATH="/mnt/SDCARD/spruce/smartpros/etc/thermal-watchdog/active_profile"

unlock_governor() {
    for file in scaling_governor scaling_min_freq scaling_max_freq; do
        chmod a+w "/sys/devices/system/cpu/cpu0/cpufreq/$file" 2>/dev/null
        chmod a+w "/sys/devices/system/cpu/cpu4/cpufreq/$file" 2>/dev/null
    done
}

lock_governor() {
    for file in scaling_governor scaling_min_freq scaling_max_freq; do
        chmod a-w "/sys/devices/system/cpu/cpu0/cpufreq/$file" 2>/dev/null
        chmod a-w "/sys/devices/system/cpu/cpu4/cpufreq/$file" 2>/dev/null
    done
}

set_cpu4() {
    [ -d /sys/devices/system/cpu/cpu4/cpufreq ] || return
    echo "$1" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
    echo -n "$2" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
    echo -n "$3" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq
}

set_thermal_profile() {
    [ -f "$THERMAL_PROFILE_PATH" ] || return
    echo "$1" > "$THERMAL_PROFILE_PATH"
}

case "$1" in
1 )
    echo "cpu save"
    set_thermal_profile conservative
    unlock_governor
    set_cpu4 ondemand 1008000 1200000
    lock_governor
    ;;
0 )
    echo "cpu normal"
    set_thermal_profile smart
    unlock_governor
    set_cpu4 ondemand 1008000 1992000
    lock_governor
    ;;
*)
    ;;
esac
