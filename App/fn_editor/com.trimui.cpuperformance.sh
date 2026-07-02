#!/bin/sh
echo "============= scene CPU Performance ============"

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

set_cpu0() {
    echo "$1" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
    echo -n "$2" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
    echo -n "$3" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
}

set_cpu4() {
    [ -d /sys/devices/system/cpu/cpu4/cpufreq ] || return
    echo "$1" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
    echo -n "$2" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
    echo -n "$3" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq
}

while [ true ]
do
	case "$1" in
	1 )
		echo "cpu performance"
		unlock_governor
		set_cpu4 performance 1992000 1992000
		lock_governor
		;;
	0 )
		echo "cpu normal"
		unlock_governor
		set_cpu4 ondemand 1008000 1992000
		lock_governor
		;;
	*)
		;;
	esac
	sleep 5
done
