#!/bin/sh

APP_DIR="/mnt/SDCARD/App"

# Detect device and export to any script sourcing updaterFunctions
INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"sun8i"*) export PLATFORM="A30" ;;
    *"TG5040"*)	export PLATFORM="SmartPro" ;;
    *"TG3040"*)	export PLATFORM="Brick"	;;
    *"0xd05"*) export PLATFORM="Flip" ;;
    *) export PLATFORM="A30" ;;
esac

if [ "$PLATFORM" = "A30" ]; then
    export BIN_DIR=/mnt/SDCARD/App/-Updater/bin
    export PATH="/mnt/SDCARD/spruce/bin:$BIN_DIR:$PATH"
    export SD_DEV="/dev/mmcblk0p1"

    export B_A="key 1 57"
    export B_B="key 1 29"
    export B_START="key 1 28"
    export B_START_2="enter_pressed" # only registers 0 on release, no 1 on press

else # if [ "$PLATFORM" = "Brick" ] || [ $PLATFORM = "SmartPro" ] || [ "$PLATFORM" = "Flip" ]; then
    export BIN_DIR=/mnt/SDCARD/App/-Updater/bin64
    export PATH="/mnt/SDCARD/spruce/bin64:$BIN_DIR:$PATH"
    export SD_DEV="/dev/mmcblk1p1"

    export B_A="key 1 305"
    export B_B="key 1 304"
    export B_START="key 1 315"
    export B_START_2="start_pressed" # only registers 0 on release, no 1.
fi

acknowledge(){
    messages_file="/var/log/messages"
	echo "ACKNOWLEDGE $(date +%s)" >> "$messages_file"

    while true; do
        last_line=$(tail -n 1 "$messages_file")

        case "$last_line" in
            *"enter_pressed"*|*"$B_A"*|*"$B_B"*)
                echo "ACKNOWLEDGED $(date +%s)" >> "$messages_file"
                break
                ;;
        esac

        sleep 0.1
    done
}

boost_processing() {
    echo "CPU Mode set to PERFORMANCE"
    for i in 0 1 2 3; do
        chmod a+w /sys/devices/system/cpu/cpu$i/online
        echo 1 >/sys/devices/system/cpu/cpu$i/online
        chmod a-w /sys/devices/system/cpu/cpu$i/online
    done
    chmod a+w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
	echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    chmod a-w /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
}

check_for_update_file() {
    echo "Searching for update file"
    UPDATE_FILE=$(find /mnt/SDCARD/ -maxdepth 1 -name "spruceV*.7z" | awk -F'V' '{print $2, $0}' | sort -n | tail -n1 | cut -d' ' -f2-)
    echo "Found update file: $UPDATE_FILE"

    if [ -z "$UPDATE_FILE" ]; then
        echo "No update file found"
        return 1
    fi
    return 0
}

check_installation_validity() {
    # Check if .tmp_update folder exists
    if [ ! -d "/mnt/SDCARD/.tmp_update" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: .tmp_update folder does not exist"
        return 1
    fi

    # Check if .tmp_update/updater file exists
    if [ ! -f "/mnt/SDCARD/.tmp_update/updater" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: .tmp_update/updater file does not exist"
        return 1
    fi

    # Both files exist, installation is valid
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation appears to be valid"
    return 0
}

get_config_value() {
    local key="$1"
    local default="$2"
    local file="/mnt/SDCARD/Saves/spruce/spruce-config.json"

    jq -r "${key} // \"$default\"" "$file"
}

kill_network_services() {
    killall -9 dropbear
    killall -9 smbd
    killall -9 sftpgo
    killall -9 syncthing
    killall -9 darkhttpd
}

read_only_check() {
    echo "Performing read-only check"
    SD_or_sd=$(mount | grep -q SDCARD && echo "SDCARD" || echo "sdcard")
    echo "Device uses /mnt/$SD_or_sd for its SD card path"
    MNT_LINE=$(mount | grep "$SD_or_sd")
    if [ -n "$MNT_LINE" ]; then
        echo "mount line for SD card: $MNT_LINE"
        MNT_STATUS=$(echo "$MNT_LINE" | cut -d'(' -f2 | cut -d',' -f1)
        if [ "$MNT_STATUS" = "ro" ] && [ -n "$SD_DEV" ]; then
            echo "SD card is mounted as RO. Attempting to remount."
            mount -o remount,rw "$SD_DEV" /mnt/"$SD_or_sd"
        else
            echo "SD card is not read-only."
        fi
    fi
}

verify_7z_content() {
    local archive="$1"
    local required_dirs=".tmp_update App spruce"
    local missing_dirs=""

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Verifying update file contents"

    # List contents of the archive and save to a temporary file
    local temp_list=$(mktemp)
    7zr l "$archive" >"$temp_list"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Archive contents:"
    cat "$temp_list"

    # Adding a skip for now
    #return 0

    for dir in $required_dirs; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Searching for directory: $dir"
        if grep -q "^.*D.*[[:space:]]$dir$" "$temp_list"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Found directory: $dir"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Directory not found: $dir"
            missing_dirs="$missing_dirs $dir"
        fi
    done

    rm -f "$temp_list"

    if [ -n "$missing_dirs" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Error: Required director(ies)$missing_dirs not found in 7z file"
        return 1
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - All required directories found in 7z file"
    return 0
}

unmount_binds() {
    PRESERVE="/mnt/sdcard /userdata /mnt/SDCARD"
    echo "[INFO] Scanning /proc/self/mountinfo for bind mounts from $SD_DEV..."
    cat /proc/self/mountinfo | while read -r line; do
    # Extract everything after the last " - ", then get the device (6th field overall)
    DEVICE=$(echo "$line" | awk -F ' - ' '{print $2}' | awk '{print $2}')
    TARGET=$(echo "$line" | awk '{print $5}')

    if [ "$DEVICE" = "$SD_DEV" ]; then
        echo "[FOUND] $TARGET mounted from $DEVICE"

        SKIP=0
        for p in $PRESERVE; do
        if [ "$TARGET" = "$p" ]; then
            SKIP=1
            echo "[SKIP] Preserved target: $TARGET"
            break
        fi
        done

        if [ "$SKIP" -eq 0 ]; then
        echo "[UMOUNT] Attempting to unmount $TARGET"
        umount "$TARGET" || echo "[ERROR] Failed to unmount $TARGET"
        fi
    fi
    done
}

rgb_led() {

    # early out
	disable="$(get_config_value '.menuOptions."RGB LED Settings".disableLEDs.selected' "False")"
	if [ "$PLATFORM" = "A30" ] || [ "$PLATFORM" = "Flip" ] || [ "$disable" = "True" ]; then
		return 0	# exit if device has no LEDs to twinkle or user opts out
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