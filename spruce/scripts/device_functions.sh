#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

get_python_path() {
    case "$PLATFORM" in
        A30)                            echo "/mnt/SDCARD/spruce/bin/python/bin/python3.10" ;;
        Brick|SmartPro|SmartProS|Flip)  echo "/mnt/SDCARD/spruce/flip/bin/python3.10" ;;
        MIYOO_MINI_FLIP)                echo "/mnt/SDCARD/spruce/miyoomini/bin/python" ;;
    esac
}

export_ld_library_path() {
    case "$PLATFORM" in
        "A30")             export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/a30/lib:/usr/miyoo/lib:/usr/lib:/lib" ;;
        "Flip")            export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:/usr/miyoo/lib:/usr/lib:/lib" ;;
        "Brick")           export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib" ;;
        "SmartPro"*)       export LD_LIBRARY_PATH="/usr/trimui/lib:/usr/lib:/lib:/mnt/SDCARD/spruce/flip/lib" ;;
        "MIYOO_MINI_FLIP") export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/miyoomini/lib/:/config/lib/:/customer/lib" ;;
    esac
}

get_sd_card_path() {
    if [ "$PLATFORM" = "Flip" ]; then
        echo "/mnt/sdcard"
    else
        echo "/mnt/SDCARD"
    fi
}

get_config_path() {
    local cfgname
    case "$PLATFORM" in
        "A30") cfgname="a30" ;;
        "Flip") cfgname="flip" ;;
        "Brick") cfgname="brick" ;;
        "SmartPro") cfgname="smartpro" ;;
        "MIYOO_MINI_FLIP") cfgname="mini-flip" ;;
        *) cfgname="unknown" ;;  # optional default
    esac

    # Return the full path
    echo "/mnt/SDCARD/Saves/${cfgname}-system.json"
}

###############################################################################
# CPU CONTROLS #
################

CPU_0_DIR=/sys/devices/system/cpu/cpu0/cpufreq
CPU_4_DIR=/sys/devices/system/cpu/cpu4/cpufreq
CONSERVATIVE_POLICY_DIR="/sys/devices/system/cpu/cpufreq/conservative"
[ "$PLATFORM" = "Flip" ] && CONSERVATIVE_POLICY_DIR="$CPU_0_DIR/conservative"

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
        if [ "$PLATFORM" = "MIYOO_MINI_FLIP" ]; then
            echo ondemand > $CPU_0_DIR/scaling_governor
        else #  official spruce device
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

            echo "$SMART_DOWN_THRESH" > $CONSERVATIVE_POLICY_DIR/down_threshold
            echo "$SMART_UP_THRESH" > $CONSERVATIVE_POLICY_DIR/up_threshold
            echo "$SMART_FREQ_STEP" > $CONSERVATIVE_POLICY_DIR/freq_step
            echo "$SMART_DOWN_FACTOR" > $CONSERVATIVE_POLICY_DIR/sampling_down_factor
            echo "$SMART_SAMPLING_RATE" > $CONSERVATIVE_POLICY_DIR/sampling_rate

            lock_governor 2>/dev/null

            log_message "CPU Mode now locked to SMART" -v
        fi
        flag_remove "setting_cpu"
    fi
}

set_performance() {
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        if [ "$PLATFORM" = "MIYOO_MINI_FLIP" ]; then
            echo performance > $CPU_0_DIR/scaling_governor        
        else #  official spruce device
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
        fi
        flag_remove "setting_cpu"
    fi
}

set_overclock() {
    if ! flag_check "setting_cpu"; then
        flag_add "setting_cpu"
        if [ "$PLATFORM" = "MIYOO_MINI_FLIP" ]; then
            echo performance > $CPU_0_DIR/scaling_governor
        else #  official spruce device
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
        fi
        flag_remove "setting_cpu"
    fi
}

# use these in conjunction with the pin_cpu binary, e.g.:
#   pin_cpu "$EMU_CPUS" -n drastic32
# would set drastic's affinity to cpus 2 and 3 on the A30.
export SYSTEM_CPU="${DEVICE_CORES_ONLINE%"${DEVICE_CORES_ONLINE#?}"}"
EMU_CPUS="${DEVICE_CORES_ONLINE#${DEVICE_CORES_ONLINE%??}}"
export EMU_CPUS="${EMU_CPUS%?},${EMU_CPUS#?}"


###############################################################################

# Vibrate the device
# Usage: vibrate [duration] [--intensity Strong|Medium|Weak]
#        vibrate [--intensity Strong|Medium|Weak] [duration]
# If no duration is provided, defaults to 50ms
# If no intensity is provided, gets value from settings
vibrate() {
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

    case "$PLATFORM" in
        "A30")
            if [ "$intensity" = "Strong" ]; then    # 100% duty cycle
                echo "$duration" >/sys/devices/virtual/timed_output/vibrator/enable
            elif [ "$intensity" = "Medium" ]; then  # 83% duty cycle
                timer=0
                while [ $timer -lt $duration ]; do
                    echo 5 >/sys/devices/virtual/timed_output/vibrator/enable
                    sleep 0.006
                    timer=$(($timer + 6))
                done &
            elif [ "$intensity" = "Weak" ]; then    # 75% duty cycle
                timer=0
                while [ $timer -lt $duration ]; do
                    echo 3 >/sys/devices/virtual/timed_output/vibrator/enable
                    sleep 0.004
                    timer=$(($timer + 4))
                done &
            else
                log_message "this is where I'd put my vibration... IF I HAD ONE"
            fi
            ;;
        "Brick" | "SmartPro" | "SmartProS" | "Flip")  
            # todo: figure out how to make lengths equal across intensity
            if [ "$intensity" = "Strong" ]; then    # 100% duty cycle
                timer=0
                echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                while [ $timer -lt $duration ]; do
                    sleep 0.002
                    timer=$(($timer + 2))
                done
                echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
            elif [ "$intensity" = "Medium" ]; then  # 83% duty cycle
                timer=0
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.005
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$(($timer + 6))
                done &
            elif [ "$intensity" = "Weak" ]; then    # 75% duty cycle
                timer=0
                while [ $timer -lt $duration ]; do
                    echo -n 1 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.003
                    echo -n 0 > /sys/class/gpio/${RUMBLE_GPIO}/value
                    sleep 0.001
                    timer=$(($timer + 4))
                done &
            fi
            ;;
    esac
}


# Call this to kill any display processes left running
# If you use display() at all you need to call this on all the possible exits of your script
display_kill() {
    if [ "$PLATFORM" != "MIYOO_MINI_FLIP" ]; then
        kill -9 $(pgrep display) 2> /dev/null
    fi
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
    [ "$PLATFORM" = "MIYOO_MINI_FLIP" ] && return 64
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


# ---------------------------------------------------------------------------
# rgb_led <zones> <effect> [color] [duration_ms] [cycles] [A30/Flip led trigger]
#
# Controls RGB LEDs on TrimUI Brick / Smart Pro.
#
# PARAMETERS:
#   <zones>        A string containing any combination of: l r m 1 2
#                  (order does not matter)
#                  Zones resolve to:
#                     l  → left LED
#                     r  → right LED
#                     m  → middle LED
#                     1  → front LED f1
#                     2  → front LED f2
#                  Example: "lrm12", "m1", "r2", "l"
#
#   <effect>       One of the following keywords or numeric equivalents:
#                     0 | off | disable      → off
#                     1 | linear | rise      → linear rise
#                     2 | breath*            → breathing pattern
#                     3 | sniff              → "sniff" animation
#                     4 | static | on        → solid color
#                     5 | blink*1            → blink pattern 1
#                     6 | blink*2            → blink pattern 2
#                     7 | blink*3            → blink pattern 3
#
#   [color]        Hex RGB color (default: "FFFFFF")
#
#   [duration_ms]  Animation duration in milliseconds (default: 1000)
#
#   [cycles]       Number of animation cycles (default: 1)
#
#   [led trigger]  none battery-charging-or-full battery-charging battery-full 
#                  battery-charging-blink-full-solid usb-online ac-online 
#                  timer heartbeat gpio default-on mmc1 mmc0
#
#
# EXAMPLES:
#   rgb_led lrm breathe FF8800 2000 3 heartbeat
#   rgb_led m2 blink1 00FFAA
#   rgb_led 12 static
#   rgb_led r off
# ---------------------------------------------------------------------------

rgb_led() {

    # early out if disabled
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	[ "$disable" = "True" ] && return 0

    # handle platforms with no rgb zones
    case "$PLATFORM" in "A30"|"Flip") 
        [ -n "$6" ] && echo "$6" > "$LED_PATH/trigger"
        return 0
    ;; esac

    if [ "$PLATFORM" = "MIYOO_MINI_FLIP" ]; then
        return 0
    fi

    # parse led zones to affect from first argument
    if [ -n "$1" ]; then
        zones=""
        for z in l r m 1 2; do
            case "$1" in
                *"$z"*) zones="$zones $z";;
            esac
        done
    else
        zones="l r m 1 2"
    fi

    # translate 1 → f1 and 2 → f2
    new_zones=""
    for z in $zones; do
        case "$z" in
            1) new_zones="$new_zones f1" ;;
            2) new_zones="$new_zones f2" ;;
            *) new_zones="$new_zones $z" ;;
        esac
    done
    zones="$new_zones"

    # parse effect to use from second argument
    case "$2" in
        0|off|disable) effect=0 ;;
        1|linear|rise) effect=1 ;;
        2|breath*) effect=2 ;;
        3|sniff) effect=3 ;;
        4|static|on) effect=4 ;;
        5|blink*1) effect=5 ;;
        6|blink*2) effect=6 ;;
        7|blink*3) effect=7 ;;
        *) effect=4 ;;
    esac

    # get color, duration, and cycles literally from args 3,4,5, with fallbacks if missing
    color=${3:-"FFFFFF"}
    duration=${4:-1000}
    cycles=${5:-1}

    # do the things
   	echo 1 > /sys/class/led_anim/effect_enable 2>/dev/null
	for zone in $zones; do
		echo "$color" > /sys/class/led_anim/effect_rgb_hex_$zone 2>/dev/null
		echo "$cycles" > /sys/class/led_anim/effect_cycles_$zone 2>/dev/null
		echo "$duration" > /sys/class/led_anim/effect_duration_$zone 2>/dev/null
		echo "$effect" > /sys/class/led_anim/effect_$zone 2>/dev/null
	done
}

rainbreathe() {
    for color in FF0000 FF8000 FFFF00 80FF00 \
                 00FF00 00FF80 00FFFF 0080FF \
                 0000FF 8000FF FF00FF FF0080; do
        rgb_led lrm12 breathe $color ${1:-2000}
        sleep ${2:-3}
    done
}


# used in principal.sh
enable_or_disable_rgb() {
    case "$PLATFORM" in
        "Brick"|"SmartPro"|"SmartProS")
            enable_file="/sys/class/led_anim/enable"
        	disable_rgb="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
            if [ "$disable_rgb" = "True" ]; then
                chmod 777 "$enable_file" 2>/dev/null
                echo 0 > "$enable_file" 2>/dev/null
                chmod 000 "$enable_file" 2>/dev/null
            else
                chmod 777 "$enable_file" 2>/dev/null
                echo 1 > "$enable_file" 2>/dev/null
                # don't lock them back afterwards
            fi
            ;;
        *)
            ;;
    esac
}

restart_wifi() {
    # Requires PLATFORM and WPA_SUPPLICANT_FILE to be set
    if [ "$PLATFORM" = "Flip" ]; then
        log_message "Restarting Wi-Fi interface wlan0 on Flip"

        # Bring the interface down and kill any running services
        ifconfig wlan0 down
        killall wpa_supplicant 2>/dev/null
        killall udhcpc 2>/dev/null

        # Bring the interface back up and reconnect
        ifconfig wlan0 up
        wpa_supplicant -B -i wlan0 -c "$WPA_SUPPLICANT_FILE"
        udhcpc -i wlan0 &
    else
        log_message "Letting stock OS restart wifi for the FLIP"
    fi
}

QRENCODE_PATH="/mnt/SDCARD/spruce/bin/qrencode"
QRENCODE64_PATH="/mnt/SDCARD/spruce/bin64/qrencode"

get_qr_bin_path() {
    if [ "$PLATFORM" = "A30" ]; then
        echo "$QRENCODE_PATH"
    else
        echo "$QRENCODE64_PATH"
    fi
}

set_path_variable() {
    case "$PLATFORM" in
        A30)               export PATH="/mnt/SDCARD/spruce/bin:$PATH" ;;
        MIYOO_MINI_FLIP)   export PATH="/mnt/SDCARD/spruce/miyoomini/bin:$PATH" ;;
        *)                 export PATH="/mnt/SDCARD/spruce/bin64:$PATH" ;;
    esac
}



enter_sleep() {
    if [ "$PLATFORM" != "MIYOO_MINI_FLIP" ]; then
        log_message "powerbutton_watchdog.sh: Entering sleep."
        [ "$PLATFORM" = "Flip" ] && echo deep >/sys/power/mem_sleep
        echo -n mem >/sys/power/state
    fi
}

get_current_volume() {
    case "$PLATFORM" in
        "Flip" ) amixer get 'SPK' | sed -n 's/.*Mono: *\([0-9]*\).*/\1/p' | tr -d '[]%' ;;
        * ) amixer get 'Soft Volume Master' | sed -n 's/.*Front Left: *\([0-9]*\).*/\1/p' | tr -d '[]%' ;;
    esac
}

set_volume() {
    new_vol="${1:-0}" # default to mute if no value supplied
    case "$PLATFORM" in
        "Flip" ) amixer cset name='SPK Volume' "$new_vol" ;;
        * ) amixer set 'Soft Volume Master' "$new_vol" ;;
    esac
}


reset_playback_pack() {
  #TODO I think this should be Flip only
  if [ "$PLATFORM" = "Flip" ] || [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "SmartProS" ]; then
    log_message "*** audioFunctions.sh: reset playback path" -v

    current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
    system_json_volume=$(cat $SYSTEM_JSON | grep -o '"vol":\s*[0-9]*' | grep -o [0-9]*)
    current_vol_name="SYSTEM_VOLUME_$system_json_volume"
    
    eval vol_value=\$$current_vol_name
    
    amixer sset 'SPK' "$vol_value%" > /dev/null
    amixer cset name='Playback Path' 0 > /dev/null
    amixer cset name='Playback Path' "$current_path" > /dev/null
  fi 
}

set_playback_path() {
  #TODO I think this should be Flip only
  if [ "$PLATFORM" = "Flip" ] || [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "SmartProS" ]; then
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
  fi
}


run_mixer_watchdog() {
    if [ "$PLATFORM" = "Flip" ] || [ "$PLATFORM" = "Brick" ] || [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "SmartPro" ] || [ "$PLATFORM" = "SmartProS" ]; then
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
    fi
}

new_execution_loop() {
    if [ "$PLATFORM" = "MIYOO_MINI_FLIP" ]; then
        # Only run if not already running
        pidof audioserver >/dev/null || audioserver &
    fi
}