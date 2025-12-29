#!/bin/sh

###############################################################################
# CPU CONTROLS #
################

CPU_0_DIR=/sys/devices/system/cpu/cpu0/cpufreq
CPU_4_DIR=/sys/devices/system/cpu/cpu4/cpufreq


get_conservative_policy_dir() {
    log_message "Failed to implement get_conservative_policy_dir()"
}

unlock_governor() {
    for file in scaling_governor scaling_min_freq scaling_max_freq; do
        chmod a+w "$CPU_0_DIR/$file"
        [ -e "$CPU_4_DIR" ] && chmod a+w "$CPU_4_DIR/$file"
    done
}

lock_governor() {
    for file in scaling_governor scaling_min_freq scaling_max_freq; do
        chmod a-w "$CPU_0_DIR/$file"
        [ -e "$CPU_4_DIR" ] && chmod a-w "$CPU_4_DIR/$file"
    done
}

# Usage:
#   cores_online            -> defaults to cores 0-3
#   cores_online "0135"     -> online cores 0,1,3,5; offline others
cores_online() {
    core_string="${1:-0123}"

    # Silently fall back on invalid input
    case "$core_string" in (*[!0-7]*) core_string=0123 ;; esac

    for cpu_path in /sys/devices/system/cpu/cpu[0-7]*; do
        [ -e "$cpu_path/online" ] || continue

        cpu="${cpu_path##*cpu}"
        case "$core_string" in
            (*"$cpu"*) val=1 ;;
            (*)        val=0 ;;
        esac

        # lock requested cpus online and all others offline
        chmod a+w "$cpu_path/online" 2>/dev/null
        echo "$val" >"$cpu_path/online" 2>/dev/null
        chmod a-w "$cpu_path/online" 2>/dev/null
    done
}

SMART_DOWN_THRESH=45
SMART_UP_THRESH=75
SMART_FREQ_STEP=3
SMART_DOWN_FACTOR=1
SMART_SAMPLING_RATE=100000
SLEEP_SAMPLING_RATE=1000000

set_smart() {
    scaling_min_freq="${1:-DEVICE_SMART_FREQ}"
    log_message "set_smart called $scaling_min_freq"

    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online 01234567   # bring all up before potentially offlining cpu0
        cores_online "$DEVICE_CORES_ONLINE"

        unlock_governor 2>/dev/null

        echo "conservative" > "$CPU_0_DIR/scaling_governor"
        echo "$scaling_min_freq" > "$CPU_0_DIR/scaling_min_freq"
        echo "$DEVICE_PERF_FREQ" > "$CPU_0_DIR/scaling_max_freq"

        if [ -e "$CPU_4_DIR" ]; then
            echo "conservative" > "$CPU_4_DIR/scaling_governor"
            echo "$scaling_min_freq" > "$CPU_4_DIR/scaling_min_freq"
            echo "$DEVICE_PERF_FREQ" > "$CPU_4_DIR/scaling_max_freq"
        fi

        CONSERVATIVE_POLICY_DIR=$(get_conservative_policy_dir)
        echo "$SMART_DOWN_THRESH" > $CONSERVATIVE_POLICY_DIR/down_threshold
        echo "$SMART_UP_THRESH" > $CONSERVATIVE_POLICY_DIR/up_threshold
        echo "$SMART_FREQ_STEP" > $CONSERVATIVE_POLICY_DIR/freq_step
        echo "$SMART_DOWN_FACTOR" > $CONSERVATIVE_POLICY_DIR/sampling_down_factor
        echo "$SMART_SAMPLING_RATE" > $CONSERVATIVE_POLICY_DIR/sampling_rate

        lock_governor 2>/dev/null

        log_message "CPU Mode now locked to SMART" -v
        flag_remove "setting_cpu"
    fi
}

set_performance() {
    log_message "set_performance called"
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online 01234567   # bring all up before potentially offlining cpu0
        cores_online "$DEVICE_CORES_ONLINE"

        unlock_governor 2>/dev/null

        echo "performance" > "$CPU_0_DIR/scaling_governor"
        echo "$DEVICE_PERF_FREQ" > "$CPU_0_DIR/scaling_max_freq"

        if [ -e "$CPU_4_DIR" ]; then
            echo "performance" > "$CPU_4_DIR/scaling_governor"
            echo "$DEVICE_PERF_FREQ" > "$CPU_4_DIR/scaling_max_freq"
        fi

        lock_governor 2>/dev/null

        log_message "CPU Mode now locked to PERFORMANCE" -v
        flag_remove "setting_cpu"
    fi
}

set_overclock() {
    log_message "set_overclock called"
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online 01234567   # bring all up before potentially offlining cpu0
        cores_online "$DEVICE_CORES_ONLINE"
        unlock_governor 2>/dev/null

        echo performance > "$CPU_0_DIR/scaling_governor"
        echo "$DEVICE_MAX_FREQ" > "$CPU_0_DIR/scaling_max_freq"
        if [ -e "$CPU_4_DIR" ]; then
            echo "performance" > "$CPU_4_DIR/scaling_governor"
            echo "$DEVICE_MAX_FREQ" > "$CPU_4_DIR/scaling_max_freq"
        fi

        lock_governor 2>/dev/null
        log_message "CPU Mode now locked to OVERCLOCK" -v
        flag_remove "setting_cpu"
    fi
}
