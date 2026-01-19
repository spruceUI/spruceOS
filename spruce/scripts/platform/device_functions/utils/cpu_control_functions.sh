#!/bin/sh

###############################################################################
# CPU CONTROLS #
################

# requires from $PLATFORM.cfg files:
# DEVICE_MIN_CORES_ONLINE
# CPU_SMART_CORES_ONLINE
# DEVICE_MAX_CORES_ONLINE
# DEVICE_POWERSAVE_LOW_FREQ
# DEVICE_POWERSAVE_HIGH_FREQ
# CPU_SMART_MIN_FREQ
# CPU_PERF_MAX_FREQ
# CPU_OVERCLOCK_MAX_FREQ
# CONSERVATIVE_POLICY_DIR

CPU_0_DIR=/sys/devices/system/cpu/cpu0/cpufreq
CPU_4_DIR=/sys/devices/system/cpu/cpu4/cpufreq

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
#   cores_online "0123"           -> cores 0-3
#   cores_online "0135"     -> online cores 0,1,3,5; offline others
cores_online() {
    [ -z "$1" ] && return  # skip empty call
    core_string="${1:-0123}"

    # TODO why silent?
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
    log_message "Setting cores online: ${core_string}"
}

# Save the current online cores to /tmp/cores_online
save_cores_online() {
    local core_list=""
    for cpu_path in /sys/devices/system/cpu/cpu[0-7]*; do
        [ -e "$cpu_path/online" ] || continue
        cpu="${cpu_path##*cpu}"
        val=$(<"$cpu_path/online")
        if [ "$val" -eq 1 ]; then
            core_list+="$cpu"
        fi
    done

    # Default to "0" if somehow no cores are online
    [ -z "$core_list" ] && core_list="0"

    echo "$core_list" > /tmp/cores_online
    log_message "Saved online cores: $core_list"
}

# Restore online cores from /tmp/cores_online
restore_cores_online() {
    if [ -f /tmp/cores_online ]; then
        cores=$(< /tmp/cores_online)
        cores_online "$cores"
    else
        log_message "No saved cores found in /tmp/cores_online"
    fi
}


# overridden on Flip by its specific implementation (for now?) that also sets gpu gov and freq
set_powersave(){
    log_message "set_powersave() called"
    if ! flag_check "setting_cpu"; then

        cores_online "$DEVICE_MIN_CORES_ONLINE"
        unlock_governor 2>/dev/null

        echo "conservative" > "$CPU_0_DIR/scaling_governor"
        echo "$DEVICE_POWERSAVE_LOW_FREQ" > "$CPU_0_DIR/scaling_min_freq"
        echo "$DEVICE_POWERSAVE_HIGH_FREQ" > "$CPU_0_DIR/scaling_max_freq"

        if [ -e "$CPU_4_DIR" ]; then
            echo "conservative" > "$CPU_4_DIR/scaling_governor"
            echo "$DEVICE_POWERSAVE_LOW_FREQ" > "$CPU_4_DIR/scaling_min_freq"
            echo "$DEVICE_POWERSAVE_HIGH_FREQ" > "$CPU_4_DIR/scaling_max_freq"
        fi

        lock_governor 2>/dev/null
        log_message "CPU locked to POWERSAVE: core(s) $DEVICE_MIN_CORES_ONLINE @ $DEVICE_POWERSAVE_LOW_FREQ to $DEVICE_POWERSAVE_HIGH_FREQ"
        flag_remove "setting_cpu"
    fi
}

set_smart() {
    SMART_DOWN_THRESH=50
    SMART_UP_THRESH=80
    SMART_FREQ_STEP=10
    SMART_DOWN_FACTOR=1
    SMART_SAMPLING_RATE=10000
    scaling_min_freq="${1:-$CPU_SMART_MIN_FREQ}"

    if [ -n "$CPU_SMART_MAX_FREQ" ]; then
        scaling_max_freq="$CPU_SMART_MAX_FREQ"
    else
        scaling_max_freq="$CPU_PERF_MAX_FREQ"
    fi

    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online "$CPU_SMART_CORES_ONLINE"

        unlock_governor 2>/dev/null

        if [ -n "$CPU_SMART_GOVENOR" ]; then
            echo "$CPU_SMART_GOVENOR" > "$CPU_0_DIR/scaling_governor"
        else
            echo "conservative" > "$CPU_0_DIR/scaling_governor"
        fi
        echo "$scaling_min_freq" > "$CPU_0_DIR/scaling_min_freq"
        echo "$scaling_max_freq" > "$CPU_0_DIR/scaling_max_freq"

        if [ -e "$CPU_4_DIR" ]; then
            echo "conservative" > "$CPU_4_DIR/scaling_governor"
            echo "$scaling_min_freq" > "$CPU_4_DIR/scaling_min_freq"
            echo "$scaling_max_freq" > "$CPU_4_DIR/scaling_max_freq"
        fi

        echo "$SMART_DOWN_THRESH" > $CONSERVATIVE_POLICY_DIR/down_threshold
        echo "$SMART_UP_THRESH" > $CONSERVATIVE_POLICY_DIR/up_threshold
        echo "$SMART_FREQ_STEP" > $CONSERVATIVE_POLICY_DIR/freq_step
        echo "$SMART_DOWN_FACTOR" > $CONSERVATIVE_POLICY_DIR/sampling_down_factor
        echo "$SMART_SAMPLING_RATE" > $CONSERVATIVE_POLICY_DIR/sampling_rate

        if [ -d "$GPU_GOVENOR_DIR" ]; then
            echo "$GPU_SMART_GOVERNOR" > "$GPU_GOVENOR_DIR/governor"
            echo "$GPU_SMART_MAX_FREQ" > "$GPU_GOVENOR_DIR/max_freq"
        fi

        lock_governor 2>/dev/null
        log_message "CPU Mode now locked to SMART: core(s) $CPU_SMART_CORES_ONLINE @ $scaling_min_freq to $CPU_PERF_MAX_FREQ"
        flag_remove "setting_cpu"
    fi
}

set_performance() {
    log_message "set_performance called"
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online "$DEVICE_MAX_CORES_ONLINE"

        unlock_governor 2>/dev/null

        echo "performance" > "$CPU_0_DIR/scaling_governor"
        # Should we specify min freq?
        echo "$CPU_PERF_MAX_FREQ" > "$CPU_0_DIR/scaling_min_freq"
        echo "$CPU_PERF_MAX_FREQ" > "$CPU_0_DIR/scaling_max_freq"

        if [ -e "$CPU_4_DIR" ]; then
            echo "performance" > "$CPU_4_DIR/scaling_governor"
            echo "$CPU_PERF_MAX_FREQ" > "$CPU_4_DIR/scaling_min_freq"
            echo "$CPU_PERF_MAX_FREQ" > "$CPU_4_DIR/scaling_max_freq"
        fi

        if [ -d "$GPU_GOVENOR_DIR" ]; then
            echo "$GPU_PERFORMANCE_GOVERNOR" > "$GPU_GOVENOR_DIR/governor"
            echo "$GPU_PERFORMANCE_MAX_FREQ" > "$GPU_GOVENOR_DIR/max_freq"
        fi

        lock_governor 2>/dev/null
        log_message "CPU Mode now locked to PERFORMANCE: $DEVICE_MAX_CORES_ONLINE @ $CPU_PERF_MAX_FREQ"
        flag_remove "setting_cpu"
        
    fi
}

set_overclock() {
    log_message "set_overclock called"
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online 01234567   # bring all up before potentially offlining cpu0
        cores_online "$DEVICE_MAX_CORES_ONLINE"
        unlock_governor 2>/dev/null

        echo performance > "$CPU_0_DIR/scaling_governor"
        # Should we specify a min frequncy?
        echo "$CPU_OVERCLOCK_MAX_FREQ" > "$CPU_0_DIR/scaling_min_freq"
        echo "$CPU_OVERCLOCK_MAX_FREQ" > "$CPU_0_DIR/scaling_max_freq"
        if [ -e "$CPU_4_DIR" ]; then
            echo "performance" > "$CPU_4_DIR/scaling_governor"
            echo "$CPU_OVERCLOCK_MAX_FREQ" > "$CPU_4_DIR/scaling_min_freq"
            echo "$CPU_OVERCLOCK_MAX_FREQ" > "$CPU_4_DIR/scaling_max_freq"
        fi

        if [ -d "$GPU_GOVENOR_DIR" ]; then
            echo "$GPU_OVERCLOCK_GOVERNOR" > "$GPU_GOVENOR_DIR/governor"
            echo "$GPU_OVERCLOCK_MAX_FREQ" > "$GPU_GOVENOR_DIR/max_freq"
        fi

        lock_governor 2>/dev/null
        log_message "CPU Mode now locked to OVERCLOCK: $DEVICE_MAX_CORES_ONLINE @ $CPU_OVERCLOCK_MAX_FREQ"
        flag_remove "setting_cpu"
    fi
}
