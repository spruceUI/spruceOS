#!/bin/sh
# --------------------------------------------------------------------------
# thermal_watchdog.sh: spruce Fan control daemon for the TrimUI Smart Pro S
# --------------------------------------------------------------------------
# Monitors temperature of little cpu cluster, big cpu cluster, and gpu once every
# 0.5s, and compares the max of the 3 to various temperature thresholds, above
# which we drive the fan at a set level. Upstepping is permitted each 0.5s cycle,
# whereas downstepping is only permitted once per 10 seconds in order to reduce
# oscillation.


FAN_CONTROL_PATH=/sys/class/thermal/cooling_device0/cur_state
BLOCK=/tmp/block_fan_downstepping

TEMP_1=50000
TEMP_2=52500
TEMP_3=55000
TEMP_4=57500
TEMP_5=60000 # 2.5 deg curve below this (more conservative)
TEMP_6=62000 # 2.0 deg curve above this (more aggressive)
TEMP_7=64000
TEMP_8=66000
TEMP_9=68000
TEMP_10=70000

LEV_0=0
LEV_1=10
LEV_2=12
LEV_3=14
LEV_4=16
LEV_5=18
LEV_6=20
LEV_7=22
LEV_8=25
LEV_9=28
LEV_10=31

get_cpu_l_temp() {
    cat /sys/class/thermal/thermal_zone0/temp
}

get_cpu_b_temp() {
    cat /sys/class/thermal/thermal_zone1/temp
}

get_gpu_temp() {
    cat /sys/class/thermal/thermal_zone2/temp
}

get_highest_temp() {
    # read each thermal zone
    cpu_l_temp=$(get_cpu_l_temp)
    cpu_b_temp=$(get_cpu_b_temp)
    gpu_temp=$(get_gpu_temp)

    # compare to see which one is hottest
    if [ "$cpu_l_temp" -ge "$cpu_b_temp" ]; then
        high_temp="$cpu_l_temp"
    else
        high_temp="$cpu_b_temp"
    fi
    if [ "$high_temp" -le "$gpu_temp" ]; then
        high_temp="$gpu_temp"
    fi

    # return whatever temp was hottest
    echo "$high_temp"
}

convert_temp_to_fan_level() {
    temp="$1"
    if [ "$temp" -ge "$TEMP_10" ]; then
        echo "$LEV_10"
    elif [ "$temp" -ge "$TEMP_9" ]; then
        echo "$LEV_9"
    elif [ "$temp" -ge "$TEMP_8" ]; then
        echo "$LEV_8"
    elif [ "$temp" -ge "$TEMP_7" ]; then
        echo "$LEV_7"
    elif [ "$temp" -ge "$TEMP_6" ]; then
        echo "$LEV_6"
    elif [ "$temp" -ge "$TEMP_5" ]; then
        echo "$LEV_5"
    elif [ "$temp" -ge "$TEMP_4" ]; then
        echo "$LEV_4"
    elif [ "$temp" -ge "$TEMP_3" ]; then
        echo "$LEV_3"
    elif [ "$temp" -ge "$TEMP_2" ]; then
        echo "$LEV_2"
    elif [ "$temp" -ge "$TEMP_1" ]; then
        echo "$LEV_1"
    else
        echo "$LEV_0"
    fi
}

block_10_seconds() {
    if [ ! -e "$BLOCK" ]; then
        touch "$BLOCK"
        sleep 10
        rm -f "$BLOCK"
    fi
}

last_level=0

while true; do

    high_temp=$(get_highest_temp)
    fan_level=$(convert_temp_to_fan_level "$high_temp")
    [ "$fan_level" -gt 31 ] && fan_level=31
    [ "$fan_level" -lt 0 ] && fan_level=0

    if [ "$fan_level" -gt "$last_level" ]; then

        last_level="$fan_level"
        echo "$fan_level" > "$FAN_CONTROL_PATH"
        block_10_seconds &

    elif [ "$fan_level" -eq "$last_level" ]; then
        : # do nothing

    else # new fan level is lower than previous fan level

        if [ ! -e "$BLOCK" ]; then
            last_level="$fan_level"
            echo "$fan_level" > "$FAN_CONTROL_PATH"
            block_10_seconds &
        fi
    fi

    sleep 0.5
done

# run the following over ADB to watch in real time:
# while true; do sleep 0.5; cat /sys/class/thermal/cooling_device0/cur_state; cat /sys/class/thermal/thermal_zone0/temp; cat /sys/class/thermal/thermal_zone1/temp; cat /sys/class/thermal/thermal_zone2/temp; done