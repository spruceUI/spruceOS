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

set_smart() {
    scaling_min_freq="${1:-DEVICE_SMART_FREQ}"

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
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        cores_online 01234567   # bring all up before potentially offlining cpu0
        cores_online "$DEVICE_CORES_ONLINE"
        unlock_governor 2>/dev/null

        case "$PLATFORM" in
            "A30")    ### A30 requires special bin to overclock beyond 1344
                /mnt/SDCARD/spruce/bin/setcpu/utils "performance" 4 1512 384 1080 1
                ;;
            *)
                echo performance > "$CPU_0_DIR/scaling_governor"
                echo "$DEVICE_MAX_FREQ" > "$CPU_0_DIR/scaling_max_freq"
                if [ -e "$CPU_4_DIR" ]; then
                    echo "performance" > "$CPU_4_DIR/scaling_governor"
                    echo "$DEVICE_MAX_FREQ" > "$CPU_4_DIR/scaling_max_freq"
                fi
                ;;
        esac

        lock_governor 2>/dev/null
        log_message "CPU Mode now locked to OVERCLOCK" -v
        flag_remove "setting_cpu"
    fi
}


rumble_gpio() {
    duration=50
    intensity="$(get_config_value '.menuOptions."System Settings".rumbleIntensity.selected' "Medium")"

    # Parse arguments in any order
    while [ $# -gt 0 ]; do
        case "$1" in
        --intensity)
            shift
            intensity="$1"
            ;;
        [0-9]*)
            duration="$1"
            ;;
        esac
        shift
    done

    case "$intensity" in
        Strong)
            timer=0
            echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
            while [ $timer -lt $duration ]; do
                sleep 0.002
                timer=$((timer + 2))
            done
            echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
            ;;
        Medium)
            timer=0
            (
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.005
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$((timer + 6))
                done
            ) &
            ;;
        Weak)
            timer=0
            (
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.003
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$((timer + 4))
                done
            ) &
            ;;
        *)
            echo "Invalid intensity: $intensity"
            return 1
            ;;
    esac
}


# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill() {
    kill -9 $(pgrep display) 2> /dev/null
}

# Call this to display text on the screen
# IF YOU CALL THIS YOUR SCRIPT NEEDS TO CALL display_kill()
# It's possible to leave a display process running
# Usage: display [options]
# Options:
#   -i, --image <path>    Image path (default: DEFAULT_IMAGE)
#   -t, --text <text>     Text to display
#   -d, --delay <seconds> Delay in seconds (default: 0)
#   -s, --size <size>     Text size (default: 36)
#   -p, --position <pos>  Text position as percentage from the top of the screen
#   (Text is offset from it's center, images are offset from the top of the image)
#   -a, --align <align>   Text alignment (left, middle, right) (default: middle)
#   -w, --width <width>   Text width (default: 600)
#   -c, --color <color>   Text color in RGB format (default: dbcda7) Spruce text yellow
#   -f, --font <path>     Font path (optional)
#   -o, --okay            Use ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE and runs acknowledge()
#   -bg, --bg-color <color> Background color in RGB format (default: 7f7f7f)
#   -bga, --bg-alpha <alpha> Background alpha value (0-255, default: 0)
#   -is, --image-scaling <scale> Image scaling factor (default: 1.0)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000
# Calling display with -o/--okay will use the ACKNOWLEDGE_IMAGE instead of DEFAULT_IMAGE
# Calling display with --confirm will use the CONFIRM_IMAGE instead of DEFAULT_IMAGE
# If using --confirm, you should call the confirm() message in an if block in your script
# --confirm will supercede -o/--okay
# You can also call infinite image layers with (next-image.png scale height side)*
#   --icon <path>         Path to an icon image to display on top (default: none)
# Example: display -t "Hello, World!" -s 48 -p top -a center -c ff0000 --icon "/path/to/icon.png"

display() {
    [ "$DISPLAY_ASPECT_RATIO" = "16:9" ] && DEFAULT_IMAGE="/mnt/SDCARD/spruce/imgs/displayTextWidescreen.png" || DEFAULT_IMAGE="/mnt/SDCARD/spruce/imgs/displayText.png"
    if [ "$BRAND" = "TrimUI" ]; then
        LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"
    fi
    ACKNOWLEDGE_IMAGE="/mnt/SDCARD/spruce/imgs/displayAcknowledge.png"
    CONFIRM_IMAGE="/mnt/SDCARD/spruce/imgs/displayConfirm.png"
    DEFAULT_FONT="/mnt/SDCARD/Themes/SPRUCE/nunwen.ttf"

    width="$DISPLAY_TEXT_ELF_WIDTH" # from ${PLATFORM}.cfg
    image="$DEFAULT_IMAGE" text=" " delay=0 size=30 position=50 align="middle" color="ebdbb2" font=""
    use_acknowledge_image=false
    use_confirm_image=false
    run_acknowledge=false
    bg_color="7f7f7f" bg_alpha=0 image_scaling=1.0
    icon_image=""
    additional_images=""
    position_set=false
    qr_url=""

    while [ $# -gt 0 ]; do
        case $1 in
            -i|--image) image="$2"; shift ;;
            -t|--text) text="$2"; shift ;;
            -d|--delay) delay="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -p|--position) position="$2"; position_set=true; shift ;;
            -a|--align) align="$2"; shift ;;
            -w|--width) width="$2"; shift ;;
            -c|--color) color="$2"; shift ;;
            -f|--font) font="$2"; shift ;;
            -o|--okay) use_acknowledge_image=true; run_acknowledge=true ;;
            --confirm) use_confirm_image=true; use_acknowledge_image=false; run_acknowledge=false ;;
            -bg|--bg-color) bg_color="$2"; shift ;;
            -bga|--bg-alpha) bg_alpha="$2"; shift ;;
            -is|--image-scaling) image_scaling="$2"; shift ;;
            --icon)
                icon_image="$2"
                if [ "$position_set" = false ]; then
                    position=80
                fi
                shift
                ;;
            --add-image)
                additional_images="$additional_images \"$2\" $3 $4 $5"
                shift 4
                ;;
            --qr)
                qr_url="$2"
                if [ "$position_set" = false ]; then
                    position=89
                fi
                shift
                ;;
            *) log_message "Unknown option: $1"; return 1 ;;
        esac
        shift
    done
    r=$(echo "$color" | cut -c1-2)
    g=$(echo "$color" | cut -c3-4)
    b=$(echo "$color" | cut -c5-6)
    bg_r=$(echo "$bg_color" | cut -c1-2)
    bg_g=$(echo "$bg_color" | cut -c3-4)
    bg_b=$(echo "$bg_color" | cut -c5-6)

    # Set font to DEFAULT_FONT if it's empty
    if [ -z "$font" ]; then
        font="$DEFAULT_FONT"
    fi

    command="LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\" display_text.elf "
    command="$command""$DISPLAY_WIDTH $DISPLAY_HEIGHT $DISPLAY_ROTATION "

    # Construct the command
    command="$command""\"$image\" \"$text\" $delay $size $position $align $width $r $g $b \"$font\" $bg_r $bg_g $bg_b $bg_alpha $image_scaling"

    # Add icon image if specified
    if [ -n "$icon_image" ]; then
        command="$command \"$icon_image\" 0.20 center middle"
    fi

    # Add CONFIRM_IMAGE if --confirm flag is used, otherwise use ACKNOWLEDGE_IMAGE if --okay flag is used
    if [ "$use_confirm_image" = true ]; then
        command="$command \"$CONFIRM_IMAGE\" 1.0 240 middle"
        delay=0
    elif [ "$use_acknowledge_image" = true ]; then
        command="$command \"$ACKNOWLEDGE_IMAGE\" 1.0 240 middle"
    fi

    # Add additional images
    if [ -n "$additional_images" ]; then
        command="$command $additional_images"
    fi

    # Generate QR code if --qr flag is used
    if [ -n "$qr_url" ]; then
        qr_image=$(qr_code -t "$qr_url")
        if [ -n "$qr_image" ]; then
            command="$command \"$qr_image\" 0.50 top middle"
        else
            log_message "Failed to generate QR code for URL: $qr_url" -v
        fi
    fi

    display_kill

    # Execute the command in the background if delay is 0
    if [ "$delay" -eq 0 ]; then
        eval "$command" &
        log_message "display command: $command"
        # Run acknowledge if -o or --okay was used and --confirm was not used
        if [ "$run_acknowledge" = true ] && [ "$use_confirm_image" = false ]; then
            acknowledge
        fi
    else
        # Execute the command and capture its output
        eval "$command"
        log_message "display command: $command"
    fi
}

# TODO I think this should be Flip only but was being ran for all platforms
reset_playback_pack() {
    log_message "*** reset playback path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    system_json_volume=$(cat $SYSTEM_JSON | grep -o '"vol":\s*[0-9]*' | grep -o [0-9]*)
    current_vol_name="SYSTEM_VOLUME_$system_json_volume"
    
    eval vol_value=\$$current_vol_name
    
    amixer sset 'SPK' "$vol_value%" > /dev/null
    amixer cset name='Playback Path' 0 > /dev/null
    amixer cset name='Playback Path' "$current_path" > /dev/null
}


# TODO I think this should be Flip only but was being ran for all platforms
set_playback_path() {
    volume_lv=$(amixer cget name='SPK Volume' | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    log_message "*** audioFunctions.sh: Volume level: $volume_lv" -v

    jack_status=$(cat /sys/class/gpio/gpio150/value) # 0 connected, 1 disconnected
    log_message "*** audioFunctions.sh: Jack status: $jack_status" -v

    # 0 OFF, 2 SPK, 3 HP
    playback_path=$([ $jack_status -eq 1 ] && echo 2 || echo 3)
    [ "$volume_lv" = 0 ] && [ "$playback_path" = 2 ] && playback_path=0
    log_message "*** audioFunctions.sh: Playback path: $playback_path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)

    amixer cset name='Playback Path' "$playback_path" > /dev/null
    # if coming off mute, ensure that there's a change so that volume doesn't spike
    ( (( current_path == 0 )) || (( current_path != playback_path )) ) && [ ! "$playback_path" = 0 ] \
      && amixer sset 'SPK' 1% > /dev/null && amixer sset 'SPK' "$volume_lv%" > /dev/null
}


run_mixer_watchdog() {
    # TODO: will need to fix for brick and tsp
    JACK_PATH=/sys/class/gpio/gpio150/value

    [ "$PLATFORM" = "Flip" ] && while true; do
        /mnt/SDCARD/spruce/bin64/inotifywait -e modify "$SYSTEM_JSON" >/dev/null 2>&1 &
        PID_INOTIFY=$!

        /mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
        PID_GPIO=$!

        wait -n

        log_message "*** mixer watchdog: change detected" -v

        kill $PID_INOTIFY $PID_GPIO 2>/dev/null

        set_playback_path
    done
}

new_execution_loop() {
    log_message "new_execution_loop nothing todo" -v
}


get_spruce_ra_cfg_location() {
    echo "/mnt/SDCARD/RetroArch/platform/retroarch-$PLATFORM.cfg"
}


launch_common_startup_watchdogs(){
    ${SCRIPTS_DIR}/powerbutton_watchdog.sh &
    ${SCRIPTS_DIR}/applySetting/idlemon_mm.sh &
    ${SCRIPTS_DIR}/low_power_warning.sh &
    ${SCRIPTS_DIR}/homebutton_watchdog.sh &
}


update_ra_config_file_with_new_setting() {
    file="$1"
    shift

    for setting in "$@"; do
        if grep -q "${setting%%=*}" "$file"; then
            sed -i "s|^${setting%%=*}.*|$setting|" "$file"
        else
            echo "$setting" >>"$file"
        fi
    done

    log_message "Updated $file"
}

