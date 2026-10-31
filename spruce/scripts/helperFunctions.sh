#!/bin/sh

# TODO: add updated table of contents/function summaries here

# This is a collection of functions that are used in multiple scripts.
# Gain access to the helper variables by adding this to the top of your script:
# . /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Load this file only once per shell.
[ "${SPRUCE_HELPERS_LOADED:-}" = "$$" ] && return 0

# constants used in multiple different helperFunctions:
export FLAGS_DIR="/mnt/SDCARD/spruce/flags"
export WPA_SUPPLICANT_FILE="/mnt/SDCARD/Saves/spruce/wpa_supplicant.conf"
export WPA_LEGACY_CONFS="/userdata/cfg/wpa_supplicant.conf /appconfigs/wpa_supplicant.conf /config/wpa_supplicant.conf"     # Where PyUI wrote saved networks before they became card-global
POWER_OFF_SCRIPT="/mnt/SDCARD/spruce/scripts/save_poweroff.sh" # used in powerbutton watchdog and sleep helper

# Export for enabling SSL support in CURL
export SSL_CERT_FILE=/mnt/SDCARD/spruce/etc/ca-certificates.crt

# Sourced here specifically because some ${PLATFORM}.sh functions depend on it.
. "/mnt/SDCARD/spruce/scripts/usb_audio_helpers.sh"


###################################################################
# Detect device and export to any script sourcing helperFunctions #
###################################################################

# MagicX A133P boards are decided by their /usr/magicx marker, not by cpuinfo:
# the A133P shares the H700's Cortex-A53 part id (0xd03) and fell into its arm.
if [ -e /usr/magicx ]; then
    # /usr/magicx/device names the model. Fall back to Z28 if missing.
    case "$(tr -d '\r\n' < /usr/magicx/device 2>/dev/null)" in
        zero40) export PLATFORM="Zero40" ;;
        xu20)   export PLATFORM="XU20" ;;
        *)      export PLATFORM="Zero28" ;;
    esac
    export PLATFORM_FAMILY="oakmoss"
else
    INFO=$(cat /proc/cpuinfo 2> /dev/null)
    case $INFO in
        *sun8i*) export PLATFORM="A30";         PLATFORM_FAMILY="tina-stock" ;;   # A33
        *TG5040*) export PLATFORM="SmartPro";   PLATFORM_FAMILY="tina-stock" ;;
        *TG3040*) export PLATFORM="Brick";      PLATFORM_FAMILY="tina-stock" ;;
        *TG5050*) export PLATFORM="SmartProS";  PLATFORM_FAMILY="tina-stock" ;;
        *TG4040*) export PLATFORM="BrickPro";   PLATFORM_FAMILY="tina-stock" ;;
        *0xd05*)                                                                # RK3566
            if grep -q '^OS_NAME="DARKMOSS"' /etc/os-release 2>/dev/null; then
                # dArkMoss stamps the spruce platform name into os-release
                # (setup_spruce_handoff-rk3566.sh). Images before that stamp carry
                # only HW_DEVICE.
                PLATFORM="$(sed -n 's/^SPRUCE_PLATFORM="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)"
                if [ -z "$PLATFORM" ]; then
                    case "$(sed -n 's/^HW_DEVICE="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)" in
                        *Miniloong*) PLATFORM="Miniloong" ;;
                        *)           PLATFORM="RGB30" ;;
                    esac
                fi
                # The RGB20SX boots the RGB30 image; its RTL8723DS gives it away.
                if [ "$PLATFORM" = "RGB30" ] && grep -qs "SDIO_ID=024C:D723" /sys/bus/sdio/devices/*/uevent; then
                    PLATFORM="RGB20SX"
                fi
                export PLATFORM
                PLATFORM_FAMILY="darkmoss"
            else
                export PLATFORM="Flip";         PLATFORM_FAMILY="tina-stock"
            fi
            ;;
        *0xd04*)                                                                # RK3326
            if grep -q '^OS_NAME="DARKMOSS"' /etc/os-release 2>/dev/null; then
                export PLATFORM="$(sed -n 's/^SPRUCE_PLATFORM="\(.*\)"/\1/p' /etc/os-release 2>/dev/null)"
                # The A10 Mini image boots the V4 too, with the V4 dtb ("... V4").
                if [ "$PLATFORM" = "A10Mini" ] && grep -qas "V4" /proc/device-tree/model; then
                    export PLATFORM="A10MiniV4"
                fi
                PLATFORM_FAMILY="darkmoss"
            else
                export PLATFORM="Pixel2"
                PLATFORM_FAMILY="twig"
            fi
            ;;
        *0xd03*)                                                                # H700
            export SPRUCE_BASEOS=1
            PLATFORM_FAMILY="h700"
            BASEOS_TARGET=$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null)
            case $BASEOS_TARGET in
                rg28xx)                 export PLATFORM="AnbernicRG28XX" ;;
                rgcubexx)               export PLATFORM="AnbernicRGCubeXX" ;;
                rg34xxsp)               export PLATFORM="AnbernicXX720480" ;;
                rg34xx|rgsp)            export PLATFORM="AnbernicXX720480NoStick" ;;
                rg35xxplus|rg35xxsp)    export PLATFORM="AnbernicXX640480NoStick" ;;
                rg40xxv)                export PLATFORM="AnbernicXX640480OneStick" ;;
                *)                      export PLATFORM="AnbernicXX640480" ;;
            esac
            ;;
        *SStar*) export PLATFORM="MiyooMini";   PLATFORM_FAMILY="miyoomini" ;;    # SSD202D: Mini, Mini V4, Mini Plus, Mini Flip
        *) export PLATFORM="MiyooMini";         PLATFORM_FAMILY="miyoomini" ;;
    esac
fi
export PLATFORM_FAMILY

platform_config="/mnt/SDCARD/spruce/scripts/platform/${PLATFORM_FAMILY}/${PLATFORM}.cfg"
if [ -z "$PLATFORM_FAMILY" ] || [ ! -f "$platform_config" ]; then
    platform_config="/mnt/SDCARD/spruce/scripts/platform/${PLATFORM}.cfg"
fi
[ ! -f "$platform_config" ] || . "$platform_config"

# Ensure all methods are defined, and just logged if missing
. "/mnt/SDCARD/spruce/scripts/platform/device.sh"

platform_functions="/mnt/SDCARD/spruce/scripts/platform/${PLATFORM_FAMILY}/${PLATFORM}.sh"
if [ -z "$PLATFORM_FAMILY" ] || [ ! -f "$platform_functions" ]; then
    platform_functions="/mnt/SDCARD/spruce/scripts/platform/${PLATFORM}.sh"
fi
[ ! -f "$platform_functions" ] || . "$platform_functions"

# Stock busybox on some devices has no timeout applet; spruce's does.
command -v timeout >/dev/null 2>&1 || timeout() { busybox timeout "$@"; }

# Every name this device answers to in an Emu config.json "devices" list, most
# specific first. Mirrors PyUI's Device.get_device_names().
#
# MUST stay in step with App/PyUI/launch.sh, which passes these same names to
# PyUI as -device. When the two disagree, the UI writes the user's emulator
# choice into one menuOption and the launcher reads a different one - which is
# exactly the bug this exists to prevent.
device_names() {
    case "$PLATFORM" in
        A30)              echo "MIYOO_A30" ;;
        Brick)            echo "TRIMUI_BRICK"; echo "TRIMUI_A133P" ;;
        BrickPro)         echo "TRIMUI_BRICK_PRO"; echo "TRIMUI_A133P" ;;
        SmartPro)         echo "TRIMUI_SMART_PRO"; echo "TRIMUI_A133P" ;;
        SmartProS)        echo "TRIMUI_SMART_PRO_S" ;;
        Flip)             echo "MIYOO_FLIP" ;;
        Pixel2)           echo "GKD_PIXEL2" ;;
        RGB30)            echo "RGB30";   echo "DARKMOSS" ;;
        RGB20SX)          echo "RGB20SX"; echo "DARKMOSS" ;;
        RG353M)           echo "RG353M"; echo "DARKMOSS" ;;
        Miniloong)        echo "MINILOONG_POCKET1"; echo "DARKMOSS" ;;
        A10Mini)          echo "A10MINI"; echo "DARKMOSS" ;;
        A10MiniV4)        echo "A10MINIV4"; echo "DARKMOSS" ;;
        XUMiniM)          echo "MAGICX_XU_MINI_M"; echo "DARKMOSS" ;;
        G350)             echo "G350";    echo "DARKMOSS" ;;
        V10)              echo "POWKIDDY_V10"; echo "DARKMOSS" ;;
        Zero28)           echo "MAGICX_ZERO28"; echo "MAGICX_A133P" ;;
        Zero40)           echo "MAGICX_ZERO40"; echo "MAGICX_A133P" ;;
        XU20)             echo "MAGICX_XU20";   echo "MAGICX_A133P" ;;
        MiyooMini)        get_miyoo_mini_variant 2>/dev/null ; echo "MIYOO_MINI_FAMILY" ;;
        AnbernicXX640480) echo "ANBERNIC_RGXX640480"; echo "ANBERNIC_RGXX" ;;
        AnbernicXX640480NoStick)  echo "ANBERNIC_RGXX640480"; echo "ANBERNIC_RGXX" ;;
        AnbernicXX640480OneStick) echo "ANBERNIC_RGXX640480"; echo "ANBERNIC_RGXX" ;;
        AnbernicXX720480) echo "ANBERNIC_RGXX720480"; echo "ANBERNIC_RGXX" ;;
        AnbernicXX720480NoStick)  echo "ANBERNIC_RGXX720480"; echo "ANBERNIC_RGXX" ;;
        AnbernicRG28XX)   echo "ANBERNIC_RG28XX";     echo "ANBERNIC_RGXX" ;;
        AnbernicRGCubeXX) echo "ANBERNIC_RGCUBEXX";   echo "ANBERNIC_RGXX" ;;
    esac

    # Ring LEDs: two of the three models share a platform with models that have
    # none, so no platform token can stand in for this. Set in AnbernicXXCommon.sh.
    if [ "${XX_RGB_MODEL:-0}" = "1" ]; then
        echo "ANBERNIC_RGXX_RGB"
    fi
    # Lid wake: the clamshells share their platforms with slabs too. See xx_lid_wake.sh.
    if command -v xx_lid_wake_supported >/dev/null 2>&1 && xx_lid_wake_supported; then
        echo "ANBERNIC_RGXX_LID_WAKE"
    fi
}

# The live RetroArch config, seeded from the .bak when absent. The configs moved
# out of RetroArch/platform in 4.4.2; that folder now holds only seeds.
ensure_ra_config_path() {
    _rac_live="/mnt/SDCARD/Saves/ra-configs/retroarch-${PLATFORM}.cfg"
    _rac_bak="/mnt/SDCARD/RetroArch/platform/retroarch-${PLATFORM}.cfg.bak"
    if [ ! -f "$_rac_live" ] && [ -f "$_rac_bak" ]; then
        mkdir -p /mnt/SDCARD/Saves/ra-configs
        cp "$_rac_bak" "$_rac_live"
    fi
    echo "$_rac_live"
    unset _rac_live _rac_bak
}

# last_key_line FILE KEY...: the latest line of a getevent capture that is one of KEY
# (each a "<type> <code>" pair as in B_A, or a Miyoo Mini key name). Not the capture's
# last line: a pad may send a second code for one press (MagicX simplepad "code2": A is
# 305 then 353, XU20 B is 304 then 158), and that rider would hide the key pressed.
last_key_line() {
    _klf=$1
    shift
    for _k in "$@"; do
        shift
        [ -n "$_k" ] && set -- "$@" -e "key $_k "
    done
    [ $# -gt 0 ] || return 0
    grep -F "$@" "$_klf" 2>/dev/null | tail -n 1
}

# Call this just by having "acknowledge" in your script
# This will pause until the user presses the A, B, or Start button
acknowledge() {
    rm -f /tmp/ge_out 2>/dev/null

    # Start getevent in the background
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    while true; do
        if line=$(last_key_line /tmp/ge_out "$B_START_2" "$B_A" "$B_B"); then
            case "$line" in
                *"key $B_START_2"* | *"key $B_A"* | *"key $B_B"*)
                    log_message "last_line: $line" -v
                    break
                    ;;
            esac
        fi

        # Prevent CPU pegging (giggity)
        sleep 0.1
    done

    kill "$GE_PID" 2>/dev/null
    display_kill
}

auto_regen_tmp_update() {
    tmp_dir="/mnt/SDCARD/.tmp_update"
    updater="/mnt/SDCARD/spruce/scripts/.tmp_update/updater"
    if ! flag_check "tmp_update_repair_attempted"; then
        [ ! -d "$tmp_dir" ] && mkdir "$tmp_dir" && flag_add "tmp_update_repair_attempted" && log_message ".tmp_update folder repair attempted. Adding tmp_update_repair_attempted flag."
        [ ! -f "$tmp_dir/updater" ] && cp "$updater" "$tmp_dir/updater"
    fi
}

confirm() {
    timeout=${1:-0}         # Default to 0 (no timeout)
    timeout_return=${2:-1}  # Default to 1 (usually 'No' or 'Cancel')
    start_time=$(date +%s)

    rm -f /tmp/ge_out 2>/dev/null
    
    # Start getevent in the background
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    RET_VAL=2
    while [ "$RET_VAL" -eq 2 ]; do
        # 1. Check for User Input
        if line=$(last_key_line /tmp/ge_out "$B_A" "$B_B"); then
            case "$line" in
                *"key $B_A"*) 
                    RET_VAL=0 
                ;;
                *"key $B_B"*) 
                    RET_VAL=1 
                ;;
            esac
        fi

        # 2. Check for Timeout (only if timeout > 0)
        if [ "$timeout" -gt 0 ]; then
            current_time=$(date +%s)
            elapsed=$((current_time - start_time))
            if [ "$elapsed" -ge "$timeout" ]; then
                RET_VAL=$timeout_return
            fi
        fi
        
        # 3. Prevent CPU pegging
        [ "$RET_VAL" -eq 2 ] && sleep 0.1
    done

    kill "$GE_PID" 2>/dev/null
    display_kill
    return "$RET_VAL"
}

# Call this to dim the screen
# Call it as a background process
dim_screen() {
    _start_backlight=$(cat "$DEVICE_BACKLIGHT_PATH")
    _end_backlight="$SYSTEM_BACKLIGHT_LEVEL_0"
    delay=0.05 # 50ms delay between each step
    
    # Start at 4 if higher (so it's faster); a platform cfg may set DIM_SCREEN_START_MAX instead
    _start_max="${DIM_SCREEN_START_MAX:-$SYSTEM_BACKLIGHT_LEVEL_4}"
    if [ "$_start_backlight" -gt "$_start_max" ]; then
        _start_backlight="$_start_max"
    fi

    # Check if another dim_screen is running
    if pgrep -f "dim_screen" | grep -v $$ >/dev/null; then
        log_message "Another dim_screen process is already running" -v
        return 1
    fi

    # Check if we're already at target brightness
    if [ "$_start_backlight" -le "$_end_backlight" ]; then
        log_message "Screen already at target brightness" -v
        return 0
    fi

    current=$_start_backlight

    while [ "$current" -gt "$_end_backlight" ]; do
        echo "$current" > "$DEVICE_BACKLIGHT_PATH"
        current=$((current - 1))
        sleep "$delay"
    done
}

calculate_progress_percent() {
    completed="${1:-0}"
    total="${2:-0}"

    if [ "$total" -le 0 ] 2>/dev/null; then
        printf '100\n'
        return 0
    fi

    percent=$((completed * 100 / total))
    [ "$percent" -lt 0 ] && percent=0
    [ "$percent" -gt 100 ] && percent=100
    printf '%s\n' "$percent"
}


# Add a flag
# Usage: flag_add "flag_name"
# Usage 2: flag_add "flag_name" --tmp   --> creates flag in /tmp/ instead, to avoid unnecessary SD writes and stuck states
flag_add() {
    local flag_name="$1"
    local dest="$FLAGS_DIR"
    if [ "$2" = "--tmp" ]; then
        dest="/tmp"
    fi
    touch "$dest/${flag_name}.lock"
}

# Check if a flag exists
# Usage: flag_check "flag_name"
# Returns 0 if the flag exists (with or without .lock extension), 1 if it doesn't


# Move the contents of $1 into $2, merging shared subdirs. Rename-based.
merge_dir() {
    mkdir -p "$2"
    for _entry in "$1"/* "$1"/.[!.]*; do
        [ -e "$_entry" ] || continue
        _name="${_entry##*/}"
        if [ -d "$_entry" ] && [ ! -L "$_entry" ] && [ -d "$2/$_name" ]; then
            ( merge_dir "$_entry" "$2/$_name" )
            rmdir "$_entry" 2>/dev/null
        else
            mv -f "$_entry" "$2/$_name" 2>/dev/null || { cp -a "$_entry" "$2/$_name" && rm -rf "$_entry"; }
        fi
    done
}

flag_check() {
    local flag_name="$1"
    if [ -f "$FLAGS_DIR/${flag_name}" ] || [ -f "$FLAGS_DIR/${flag_name}.lock" ] || [ -f "/tmp/${flag_name}.lock" ]; then
        return 0
    else
        return 1
    fi
}

# Remove a flag
# Usage: flag_remove "flag_name"
flag_remove() {
    local flag_name="$1"
    rm -f "$FLAGS_DIR/${flag_name}.lock"
    rm -f "/tmp/${flag_name}.lock"
}

# Returns the path of the current theme
# Use by doing        theme_path=$(get_current_theme_path)
# Use files inside themes to make your apps!
get_current_theme_path() {

    # check if config file exists
    if [ ! -f "$SYSTEM_JSON" ]; then
        log_message "Error: Configuration file not found at $SYSTEM_JSON"
        return 1
    fi

    # Extract "theme" from JSON, ignoring errors
    theme_name=$(jq -r '.theme' "$SYSTEM_JSON")

    # If "theme" is empty
    if [ -z "$theme_name" ]; then
        log_message "Error: Could not retrieve theme name from $SYSTEM_JSON"
        return 1
    fi

    echo "$theme_name"
}

# To support themes in your apps do         [   eval "$(get_current_theme)"    ]
# Doing this will unlock dynamic variables that will give you fast access to some
# common theme files and values. These dynamic variable are: $THEME_PATH, $THEME_BG etc.
#
# Code example:
#
# eval "$(get_current_theme)"
# echo "Current theme path:         $THEME_PATH"
# echo "Background image path:      $THEME_BG"
# echo "Font path:                  $THEME_FONT"
# echo "Font size:                  $THEME_FONT_SIZE"
# echo "Font color:                 $THEME_FONT_COLOR"
# echo "Left arrow icon:            $THEME_LEFT"
# echo "Right arrow icon:           $THEME_RIGHT"
# echo "Logo:                       $THEME_LOGO"
# echo "OK icon:                    $THEME_OK"
# echo "Home button icon:           $THEME_HOME"
# echo "A button icon:              $THEME_A"
# echo "B button icon:              $THEME_B"
# echo "L2 button icon:             $THEME_L2"
# echo "R2 button icon:             $THEME_R2"
# echo "X button icon:              $THEME_X"
# echo "Y button icon:              $THEME_Y"
# echo "START button icon:          $THEME_START"
# echo "Information icon:           $THEME_INFO"
# echo "Folder icon:                $THEME_FOLDER"
# echo "SD/TF card icon:            $THEME_SD"
# echo "Wifi icon:                  $THEME_WIFI"
# echo "Shutdown icon:              $THEME_SHUTDOWN"
# echo "Reset icon:                 $THEME_RESET"
# echo "Star icon:                  $THEME_STAR"
# echo "Expert Apps icon:           $THEME_EXPERT_APPS"
get_current_theme() {
    # gets current theme path
    theme_path=$(get_current_theme_path)
    json_path="$theme_path/config.json"

    # checks if path exists
    if [ -d "$theme_path" ]; then
        # Export theme paths
        echo "THEME_PATH=\"$theme_path\""
        echo "THEME_BG=\"$theme_path/skin/background.png\""
        echo "THEME_LEFT=\"$theme_path/skin/icon-left-arrow-24.png\""
        echo "THEME_RIGHT=\"$theme_path/skin/icon-right-arrow-24.png\""
        echo "THEME_LOGO=\"$theme_path/skin/app-loading-05.png\"" #need to discuss this
        echo "THEME_OK=\"$theme_path/skin/icon-OK.png\""
        echo "THEME_HOME=\"$theme_path/skin/ic-MENU.png\""
        echo "THEME_A=\"$theme_path/skin/icon-A-54.png\""
        echo "THEME_B=\"$theme_path/skin/icon-B-54.png\""
        echo "THEME_L2=\"$theme_path/skin/icon-L2.png\""
        echo "THEME_R2=\"$theme_path/skin/icon-R2.png\""
        echo "THEME_X=\"$theme_path/skin/icon-x.png\""
        echo "THEME_Y=\"$theme_path/skin/icon-y.png\""
        echo "THEME_START=\"$theme_path/skin/icon-START.png\""
        echo "THEME_INFO=\"$theme_path/skin/icon-device-info-48.png\""
        echo "THEME_FOLDER=\"$theme_path/skin/icon-folder.png\""
        echo "THEME_SD=\"$theme_path/skin/icon-TF.png\""
        echo "THEME_WIFI=\"$theme_path/skin/icon-setting-wifi.png\""
        echo "THEME_SHUTDOWN=\"$theme_path/skin/icon-Shutdown.png\""
        echo "THEME_RESET=\"$theme_path/skin/icon-factory-reset-48.png\""
        echo "THEME_STAR=\"$theme_path/skin/nav-favorite-f.png\""
        echo "THEME_EXPERT_APPS=\"$theme_path/icons/App/expertappswitch.png\""

        # Extract values from config JSON using jq
        if [ -f "$json_path" ]; then
            THEME_FONT_TITLE=$(jq -r '.list.font' "$json_path")
            THEME_FONT="$theme_path/$THEME_FONT_TITLE"
            THEME_FONT_SIZE=$(jq -r '.list.size' "$json_path")
            THEME_FONT_COLOR=$(jq -r '.list.color' "$json_path")

            echo "THEME_FONT=\"$THEME_FONT\""
            echo "THEME_FONT_SIZE=\"$THEME_FONT_SIZE\""
            echo "THEME_FONT_COLOR=\"$THEME_FONT_COLOR\""
        else
            echo "Error: JSON config file not found at $json_path."
            return 1
        fi
    else
        echo "Error: theme located in $theme_path doesn't exist."
        return 1
    fi
}

get_version() {
    spruce_file="/mnt/SDCARD/spruce/spruce"

    if [ ! -f "$spruce_file" ]; then
        echo "0"
        return 1
    fi

    version=$(cat "$spruce_file" | tr -d '[:space:]')

    if [ -z "$version" ]; then
        echo "0"
        return 1
    fi

    # Updated regex to handle nightly versions
    # e.g., 3.3.1-20250123
    if echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)*(-([A-Za-z]+|[0-9]{8}))?$'; then
        echo "$version"
        return 0
    else
        echo "0"
        return 1
    fi
}

# Latest release of a GitHub repo as x.y.z, or nothing when offline. Tries
# for about a minute so a boot-time caller can wait for WiFi to come up.
github_latest_version() {
    wifi_available_on_device || return 1
    [ "$(jq -r '.wifi' "$SYSTEM_JSON" 2>/dev/null)" = "1" ] || return 1
    for _try in 1 2 3; do
        _tag="$(curl -sf -m 20 "https://api.github.com/repos/$1/releases/latest" | jq -r '.tag_name // empty' | sed 's/^[vV]//')"
        case "$_tag" in
            [0-9]*.[0-9]*.[0-9]*) echo "$_tag"; return 0 ;;
        esac
        [ "$_try" -lt 3 ] && sleep 20
    done
    return 1
}

# True when x.y.z $1 is older than $2.
version_older_than() {
    [ "$(printf '%s' "$1" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')" -lt \
      "$(printf '%s' "$2" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')" ] 2>/dev/null
}

# The GitHub project this device's BaseOS build comes from, by its BASEOS_TARGET.
baseos_repo() {
    case "$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null | tr -d '"')" in
        my355) echo "apommel/baseos-my355" ;;
        *) echo "pvaibhav/BaseOS" ;;
    esac
}

# "true" when the installed BaseOS is older than the latest release of its project
# (TARGET_BASEOS_VERSION from the platform cfg offline). Unreadable: "false".
baseos_fw_needs_update() {
    _have="$(sed -n 's/^BASEOS_VERSION=//p' /etc/baseos-release 2>/dev/null | tr -d '"')"
    _want="$(github_latest_version "$(baseos_repo)")" || _want="$TARGET_BASEOS_VERSION"
    baseos_version_older "$_have" "$_want" && echo "true" || echo "false"
}

# A .bosupd for this model put at the root of the card by hand.
baseos_local_update_file() {
    _target="$(sed -n 's/^BASEOS_TARGET=//p' /etc/baseos-release 2>/dev/null | tr -d '"')"
    [ -n "$_target" ] && ls /mnt/SDCARD/baseos-"$_target"-*.bosupd 2>/dev/null | sort | tail -n 1
}

# True when BaseOS version $1 is older than $2: by x.y.z, and a pre-release (1.2.0-beta.1)
# before its own release. Status 2 when either is not x.y.z[-suffix].
baseos_version_older() {
    _bv_a="${1%%-*}"
    _bv_b="${2%%-*}"
    case "$_bv_a" in ''|*[!0-9.]*) return 2 ;; esac
    case "$_bv_b" in ''|*[!0-9.]*) return 2 ;; esac
    version_older_than "$_bv_a" "$_bv_b" && return 0
    version_older_than "$_bv_b" "$_bv_a" && return 1
    [ "$_bv_a" != "$1" ] && [ "$_bv_b" = "$2" ]
}

get_version_complex() {
    base_version=$(get_version)

    # Ensure we got a valid base version
    if [ -z "$base_version" ] || [ "$base_version" = "0" ]; then
        echo "$base_version"
        return 1
    fi

    version_pattern="/mnt/SDCARD/${base_version}-*"
    
    # Find any matching version file (nightly)
    test_file=$(ls $version_pattern 2>/dev/null | head -n 1)

    if [ -n "$test_file" ]; then
        test_version=$(basename "$test_file")
        echo "$test_version"
    else
        echo "$base_version"
    fi
}

# Call this like:
# log_message "Your message here"
# To output to a custom log file, set the variable within your script:
# log_file="/mnt/SDCARD/App/MyApp/spruce.log"
# This will log the message to the spruce.log file in the Saves/spruce folder
#
# Usage examples:
# Log a regular message:
#    log_message "This is a regular log message"
# Log a verbose message (only logged if log_verbose was called):
#    log_message "This is a verbose log message" -v
# Log to a custom file:
#    log_message "Custom file log message" "" "/path/to/custom/log.file"
# Log a verbose message to a custom file:
#    log_message "Verbose custom file log message" -v "/path/to/custom/log.file"
log_file="/mnt/SDCARD/Saves/spruce/spruce.log"
log_message() {
    message="$1"
    verbose_flag="${2:-}"
    custom_log_file="${3:-$log_file}"

    # Check if it's a verbose message and if verbose logging is not enabled
    [ "$verbose_flag" = "-v" ] && ! flag_check "log_verbose" && return

    # Handle custom log file
    if [ "$custom_log_file" != "$log_file" ]; then
        mkdir -p "$(dirname "$custom_log_file")"
        touch "$custom_log_file"
    fi

    printf '%s%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${verbose_flag:+ -v}" "$message" | tee -a "$custom_log_file"
}

# Call this to toggle verbose logging
# After this is called, any log_message calls will output to the log file if -v is passed
# USE THIS ONLY WHEN DEBUGGING, IT WILL GENERATE A LOT OF LOG FILE ENTRIES
# Remove it from your script when done.
# Can be used as a toggle: calling it once enables verbose logging, calling it again disables it
log_verbose() {
    calling_script=$(basename "$0")
    if flag_check "log_verbose"; then
        flag_remove "log_verbose"
        log_message "Verbose logging disabled in script: $calling_script"
    else
        flag_add "log_verbose"
        log_message "Verbose logging enabled in script: $calling_script"
    fi
}

log_precise() {
    message="$1"
    date_part=$(date '+%Y-%m-%d %H:%M:%S')
    uptime_part=$(cut -d ' ' -f 1 /proc/uptime)
    timestamp="${date_part}.${uptime_part#*.}"
    printf '%s %s\n' "$timestamp" "$message" >>"$log_file"
}

# battery_snapshot EVENT: one line per power-off and per boot in Saves/spruce/battery-history.log
# (epoch, event, percent, gauge raw percent, mV), so drain while the device was off can be read as
# the difference between a "poweroff" line and the next "boot" line. Kept to the last 200 lines.
battery_snapshot() {
    _bs_log=/mnt/SDCARD/Saves/spruce/battery-history.log
    _bs_raw=$(cat "$BATTERY/capacity" 2>/dev/null)
    _bs_uv=$(cat "$BATTERY/voltage_now" 2>/dev/null)
    case "$_bs_uv" in ''|*[!0-9]*) _bs_mv=- ;; *) [ "$_bs_uv" -gt 100000 ] && _bs_mv=$((_bs_uv / 1000)) || _bs_mv=$_bs_uv ;; esac
    printf '%s %s %s%% raw=%s%% %smV\n' "$(date +%s)" "$1" "$(device_get_battery_percent 2>/dev/null)" \
        "${_bs_raw:--}" "$_bs_mv" >> "$_bs_log" 2>/dev/null
    if [ "$(wc -l < "$_bs_log" 2>/dev/null || echo 0)" -gt 200 ]; then
        tail -n 200 "$_bs_log" > "$_bs_log.tmp" 2>/dev/null && mv "$_bs_log.tmp" "$_bs_log"
    fi
    unset _bs_log _bs_raw _bs_uv _bs_mv
}

low_battery_check() {
    if flag_check "low_battery"; then
        CAPACITY=$(device_get_battery_percent)
        start_pyui_message_writer
        log_and_display_message "Battery has $CAPACITY% left. Charge or shutdown your device."
        sleep 1
        acknowledge
        flag_remove "low_battery"
        stop_pyui_message_writer
    fi
}

hide_or_unhide_AccentColor_app() {
    _cur_theme="$(get_pyui_config_value ".theme" "SPRUCE")"
    _theme_path="/mnt/SDCARD/Themes/${_cur_theme}"
    _config="/mnt/SDCARD/App/AccentColor/config.json"

    # Rewriting an unchanged file still forces FAT directory writes on every
    # menu restart. Only touch the app config when its visibility changes.
    if [ -d "${_theme_path}/accent" ]; then
        if grep -qF '"#label"' "$_config"; then
            sed -i 's|"#label"|"label"|' "$_config"
        fi
    elif grep -qF '"label"' "$_config"; then
        sed -i 's|"label"|"#label"|' "$_config"
    fi
}

# Generate a QR code
# Usage: qr_code -t "text" -s "size" -l "level" -o "output"
# If no output is provided, the QR code will be saved to /tmp/tmp/qr.png
#   QR_CODE=$(qr_code -t "https://www.google.com")
#   display -i "$QR_CODE" -t "DT: QR Code" -d 5
qr_code() {
    text=""
    size=3
    level="M"
    output="/mnt/SDCARD/spruce/tmp/qr.png"

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--text) text="$2"; shift ;;
            -s|--size) size="$2"; shift ;;
            -l|--level) level="$2"; shift ;;
            -o|--output) output="$2"; shift ;;
            *) text="$1" ;;  # If no flag, assume it's the text
        esac
        shift
    done

    # Ensure text is provided
    if [ -z "$text" ]; then
        log_message "QR Code error: No text provided" -v
        return 1
    fi

    # Make tmp directory if it doesn't exist
    mkdir -p "/mnt/SDCARD/spruce/tmp"

    # Generate QR code
    if qrencode -o "$output" -s "$size" -l "$level" -m 2 "$text" >/dev/null 2>&1; then
        echo "$output"
        return 0
    else
        log_message "QR Code generation failed"
        echo ""
        return 1
    fi
}


# returns 0 if SD is read-only or write test fails
# returns 1 if SD is writable
read_only_check() {
    log_message "Performing read-only check"
    MNT_LINE=$(mount | grep -m1 $SD_DEV)
    log_message "mount line for SD card: $MNT_LINE"

    mkdir -p /mnt/SDCARD/spruce/flags 2>/dev/null
    TEST_FILE="/mnt/SDCARD/spruce/flags/test-$(date +%s)"
    touch "$TEST_FILE"
    echo "testing!" > "$TEST_FILE"
    if [ ! -e "$TEST_FILE" ]; then
        # this log will most likely fail to write lol
        log_message "Unable to create write test file. SD card is likely mounted read-only."
        return 0
    elif ! grep -q "testing!" "$TEST_FILE"; then
        log_message "Test file created successfully but did not contain test message. SD card likely remounted as read-only."
        return 0
    else
        log_message "SD card does not appear to be read only"
        # A passing write test is authoritative: the card is writable. Return
        # that now rather than falling through to the mount-line check below.
        # That check reports read-only whenever SD_DEV is absent from the mount
        # table, because an `if` with no matching branch and no else exits 0 -
        # so on a base whose TF2 device node does not match SD_DEV, a perfectly
        # writable card is called read-only forever and repairSD loops.
        rm -f "$TEST_FILE"
        return 1
    fi
}


run_upgrade_scripts() {
    UPGRADE_SCRIPTS_DIR="/mnt/SDCARD/App/spruceRestore/UpgradeScripts"
    last_update_file="/mnt/SDCARD/App/spruceRestore/.lastUpdate"

    if [ -f "$last_update_file" ]; then
        current_version=$(grep "spruce_version=" "$last_update_file" | cut -d'=' -f2 | tr -d '\r\n')
    else
        current_version="2.0.0"
    fi

    log_message "Upgrade scripts: current version is $current_version"

    if [ ! -d "$UPGRADE_SCRIPTS_DIR" ]; then
        log_message "Upgrade scripts: directory not found, skipping"
        return 0
    fi

    is_developer_mode=$(flag_check "developer_mode" && echo "true" || echo "false")
    is_tester_mode=$(flag_check "tester_mode" && echo "true" || echo "false")
    allow_same_version=0

    if [ "$is_developer_mode" = "true" ] || [ "$is_tester_mode" = "true" ]; then
        allow_same_version=1
        log_message "Upgrade scripts: dev/tester mode detected, allowing same version upgrades"
    fi

    cd "$UPGRADE_SCRIPTS_DIR" || return 1

    for script in *.sh; do
        [ -f "$script" ] || continue

        script_version=$(echo "$script" | cut -d'.' -f1-3)

        version_compare=$(echo "$current_version $script_version" | awk '{
            split($1, a, ".")
            split($2, b, ".")
            for (i = 1; i <= 3; i++) {
                if (a[i] < b[i]) { print "older"; exit }
                else if (a[i] > b[i]) { print "newer"; exit }
            }
            print "equal"
        }')

        if [ "$version_compare" = "older" ] || ([ "$version_compare" = "equal" ] && [ $allow_same_version -eq 1 ]); then
            log_message "Upgrade scripts: running $script"
            output=$(sh "$script" 2>&1)
            exit_status=$?
            log_message "Upgrade scripts: output from $script:"
            echo "$output" >> "${log_file:-/mnt/SDCARD/Saves/spruce/spruce.log}"

            if [ $exit_status -eq 0 ]; then
                log_message "Upgrade scripts: $script completed successfully"
                echo "spruce_version=$script_version" > "$last_update_file"
                current_version=$script_version
            else
                log_message "Upgrade scripts: $script failed with exit status $exit_status"
                cd - > /dev/null
                return 1
            fi
        else
            log_message "Upgrade scripts: skipping $script (current $current_version >= $script_version)"
        fi
    done

    cd - > /dev/null
    log_message "Upgrade scripts: completed. Current version: $current_version"
    return 0
}


##########     NEW PYUI-BASED SETTING SYSTEM     ##########

# Get spruce-specific settings from spruce-config.json
# example usage:
# SMB_ENABLED="$(get_config_value '.menuOptions."Network Settings".enableSMB.selected' "True")"
get_config_value() {
    local key="$1"
    local default="$2"
    local file="/mnt/SDCARD/Saves/spruce/spruce-config.json"

    jq -r "${key} // \"$default\"" "$file"
}

###########################################################
##########     PYUI MESSAGE WRITER     ##########

# The writer's socket. PyUI's menu listens on it too, as "realtimeMessagePort" in
# App/PyUI/py-ui-config.json, so the two must match.
PYUI_MESSAGE_PORT=50980

start_pyui_message_writer() {
    # $1 = 0 to not wait, anything else to wait
    wait_for_listener="$1"

    # PyUI runs this script and listens itself (App/PyUI/main-ui/apps/script_app.py).
    if [ -n "$PYUI_HOSTS_MESSAGES" ]; then
        log_message "PyUI shows this script's messages; no message writer needed."
        return 0
    fi

    ifconfig lo up
    ifconfig lo 127.0.0.1

    # Check if PyUI is already running with the realtime port argument
    if pgrep -f "sgDisplayRealtimePort" >/dev/null; then
        log_message "Real Time message listener already running."
        return
    fi
    
    rm -f /mnt/SDCARD/App/PyUI/realtime_message_network_listener.txt
    log_message "Starting Real Time message listener on port $PYUI_MESSAGE_PORT"
    /mnt/SDCARD/App/PyUI/launch.sh -msgDisplayRealtimePort "$PYUI_MESSAGE_PORT" &

    if [ "$wait_for_listener" != "0" ]; then
        log_message "Waiting for realtime_message_network_listener to appear..."
        listener_tries=0
        while [ ! -e "/mnt/SDCARD/App/PyUI/realtime_message_network_listener.txt" ]; do
            listener_tries=$((listener_tries + 1))
            if [ "$listener_tries" -ge 150 ]; then
                log_message "Realtime message listener never appeared after 15s; continuing without it."
                return 1
            fi
            sleep 0.1
        done
        log_message "Realtime message network listener detected."
    fi
}


kill_pyui_message_writer() {

    # Check if PyUI is already running with the realtime port argument
    pids=$(pgrep -f "sgDisplayRealtimePort" | awk '{print $1}')

    if [ -n "$pids" ]; then
        log_message "Real Time message listener is running. Killing it..."
        display_message "$(printf '{"cmd":"EXIT_APP","args":[]}')"
        sleep 0.5

        # Kill all matching PIDs
        for pid in $pids; do
            kill "$pid" 2>/dev/null
        done
        # Optionally wait for processes to exit
        sleep 1
    fi    

}

stop_pyui_message_writer() {
    # PyUI runs this script and keeps showing its messages: there is no writer to stop, and
    # freemma would blank the menu's screen and free video memory the menu still uses.
    if [ -n "$PYUI_HOSTS_MESSAGES" ]; then
        return 0
    fi
    kill_pyui_message_writer
    freemma >/dev/null 2>&1 # where a device has it (the Miyoo Mini)
}

display_message() {
    local message="$1"
    [ -z "$message" ] && return 0

    # We use double quotes for the -c string so we can use single quotes inside.
    # We pass "$message" and the port as the final arguments, which Python picks up as
    # sys.argv[1] and sys.argv[2]
    "$(get_python_path)" -c 'import socket, sys;
try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.5)
    s.connect(b"\0" + sys.argv[2].encode())
    s.sendall((sys.argv[1] + "\n").encode("utf-8"))
    s.close()
except Exception as e:
    print(f"Sender Error: {e}", file=sys.stderr)
' "$message" "$PYUI_MESSAGE_PORT"
}

json_escape() {
    # Callers write a two-character \n where they want a line break - that is the
    # convention at every display_* call site in the tree, and before this
    # function existed the sequence passed straight into the JSON string and
    # decoded to a real newline. Escaping backslashes without undoing it first
    # doubles it, and the UI draws a literal \n instead of breaking the line.
    #
    # So fold it back to a real newline up front; the awk below re-emits it as a
    # JSON \n. The replacement is a backslash-newline rather than \n because
    # busybox sed does not read \n in the RHS as a newline.
    printf '%s' "$1" | sed -e 's/\\n/\
/g' -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
        -e 's/\t/\\t/g' -e 's/\r/\\r/g' | awk 'NR>1{printf "\\n"} {printf "%s", $0} END{}'
}

log_and_display_message(){
    log_message "$1"
    display_message "$(printf '{"cmd":"MESSAGE","args":["%s"]}' "$(json_escape "$1")")"
}

display_option_list(){
    log_message "Display option list $1"
    display_message "$(printf '{"cmd":"OPTION_LIST","args":["%s"]}' "$(json_escape "$1")")"
}

display_text_with_percentage_bar(){
    # $1 = Text e.g. "Hello"
    # $2 = The percentage complete e.g. 75
    # $3 = Optional bottom text
    log_message "Display text with percentage bar $1 $2"
    if [ $# -eq 2 ]; then
        display_message "$(printf '{"cmd":"TEXT_WITH_PERCENTAGE_BAR","args":["%s","%s"]}' "$(json_escape "$1")" "$2")"
    else
        display_message "$(printf '{"cmd":"TEXT_WITH_PERCENTAGE_BAR","args":["%s","%s","%s"]}' "$(json_escape "$1")" "$2" "$(json_escape "$3")")"
    fi
}

# BaseOS ships busybox wget as /usr/bin/wget. It rejects every GNU long option
# outright - --quiet, --no-check-certificate and --max-redirect each make it
# print its usage block and exit non-zero - and even with busybox-safe flags it
# cannot finish an HTTPS transfer, because there is no ssl_helper on the system:
# it connects, prints "note: TLS certificate validation not implemented", then
# writes nothing. The GNU wget we ship in spruce/bin64 is no escape either - on
# BaseOS it will not load, for want of libpcre.so.1 and then libuuid.so.1.
#
# curl is present and working on every platform we ship, so it is the transport
# here, with busybox-safe wget kept as a fallback. Certificates are verified
# against the bundled CA file (SSL_CERT_FILE) first; only a TLS failure retries
# with -k, which preserves the --no-check-certificate behaviour these downloads
# have always had on firmware whose TLS stack cannot use the bundle.
download_url_to_file() {
    # $1 = remote url, $2 = destination path
    if command -v curl >/dev/null 2>&1; then
        # -f so an HTTP error exits non-zero and leaves no file behind, which is
        # what wget did and what every caller here assumes. curl's own message
        # goes to the log rather than to stderr, where it would paint over the
        # UI the calling app is drawing.
        curl_error="$(curl -sSL -f --connect-timeout 15 -o "$2" "$1" 2>&1)"
        curl_result=$?
        case "$curl_result" in
            35|51|58|59|60|77)
                log_message "download_url_to_file: TLS verification failed for $1 (curl $curl_result: $curl_error); retrying without certificate verification"
                curl_error="$(curl -sSLk -f --connect-timeout 15 -o "$2" "$1" 2>&1)"
                curl_result=$?
                ;;
        esac
        [ "$curl_result" -ne 0 ] && log_message "download_url_to_file: curl failed for $1 - $curl_error"
        return "$curl_result"
    else
        wget -q -O "$2" "$1"
    fi
}

# Any HTTP response counts; -k so a wrong clock doesn't read as offline.
internet_reachable() {
    curl -sk -o /dev/null -m 5 --connect-timeout 3 "${1:-https://spruceui.github.io}"
}

get_remote_filesize_bytes() {
    url="$1"
    if command -v curl >/dev/null 2>&1; then
        # Headers only, following redirects. A GitHub release asset 302s to a
        # storage host, so several Content-Length lines come back and the last
        # one belongs to the asset itself.
        curl -sILk --connect-timeout 15 "$url" 2>/dev/null | grep -i 'Content-Length' | tail -n1 | awk '{print $2}' | tr -d '\r\n'
    else
        wget -S --spider -q -O /dev/null "$url" 2>&1 | grep -i 'Content-Length' | tail -n1 | awk '{print $2}' | tr -d '\r\n'
    fi
}

download_and_display_progress() {
	BAD_IMG="/mnt/SDCARD/spruce/imgs/notfound.png"
    remote_url="$1"
    local_path="$2"
    display_name="$3"
    final_size_bytes="$4"

    if [ -z "$final_size_bytes" ]; then
        final_size_bytes="$(get_remote_filesize_bytes "$remote_url")"
    fi

    download_url_to_file "$remote_url" "$local_path" &
    download_pid=$!

	{
		sleep 0.1
		# Watch the transfer we started rather than asking whether any wget is
		# running - that global match also caught unrelated downloads, and it
		# stopped seeing this one at all once the transport was no longer wget.
		while kill -0 "$download_pid" 2>/dev/null; do
			current_size=$(ls -ln "$local_path" 2>/dev/null | awk '{print $5}')
			[ -z "$current_size" ] && current_size=0
			[ -z "$final_size_bytes" ] && final_size_bytes=1
			percent_complete="$(((current_size * 100) / final_size_bytes))"
			[ "$percent_complete" -gt 100 ] && percent_complete=100
            current_mb="$((current_size / 1024 / 1024))"
            final_mb="$((final_size_bytes / 1024 / 1024))"
			display_text_with_percentage_bar "Now downloading $display_name!" "$percent_complete" "$current_mb MB / $final_mb MB"
			sleep 0.1
		done 
	} &
	progress_pid=$!

	wait "$download_pid"
	download_result=$?
	wait "$progress_pid" 2>/dev/null

	if [ "$download_result" -ne 0 ]; then
		display_image_and_text "$BAD_IMG" 35 25 "Unable to download $display_name. Please try again later." 75
		sleep 4
		rm -f "$local_path" 2>/dev/null
        sync
		return 1
    else
        sync
        return 0
	fi
}

display_image_and_text() {
    # Full form (5 args):
    # $1 = image path
    # $2 = image size (%)
    # $3 = image vertical offset (%)
    # $4 = text
    # $5 = text height (%)

    # Abridged form (only 2 args):
    # $1 = image path
    # $2 = text

    if [ $# -eq 2 ]; then
        img="$1"
        text="$2"
        size="35"
        img_y="25"
        text_y="75"
    else
        img="$1"
        size="${2:-25}"
        img_y="${3:-25}"
        text="$4"
        text_y="${5:-75}"
    fi

    log_message "Display image and text $img $size $img_y $text $text_y"

    display_message "$(printf \
        '{"cmd":"IMAGE_AND_TEXT","args":["%s","%s","%s","%s","%s"]}' \
        "$(json_escape "$img")" "$(json_escape "$text")" "$size" "$img_y" "$text_y"
    )"
}

get_pyui_config_value() {
    local key="$1"
    local default="$2"

    jq -r "${key} // \"$default\"" "$SYSTEM_JSON"
}


# EXAMPLE: set_pyui_config_value '.theme' "SPRUCE"
set_pyui_config_value() {
    local key="$1"
    local value="$2"
    local tmp="${SYSTEM_JSON}.tmp"

    jq "${key} = \$value" --arg value "$value" "$SYSTEM_JSON" > "$tmp" &&
        mv "$tmp" "$SYSTEM_JSON"
}

map_color_name_to_hex() {
    name="$1"
    case "$name" in
        "Red")          hex=FF0000 ;;
        "Pink")         hex=FF3333 ;;
        "Fuchsia")      hex=FF0022 ;;
        "Purple")       hex=FF00FF ;;
        "Dark Purple")  hex=2200CC ;;
        "Blue")         hex=0000FF ;;
        "Cyan")         hex=00FFFF ;;
        "Teal")         hex=00FF22 ;;
        "Green")        hex=00FF00 ;;
        "Yellow")       hex=FFFF00 ;;
        "Orange")       hex=FF1100 ;;
        *)              hex=FFFFFF ;;
    esac
    echo "$hex"
}

rgb_leds_enabled() {
    [ "$(get_config_value '.menuOptions."RGB LED Settings".enableLEDs.selected' "Off")" = "On" ]
}

# led_zone_settings with each setting's selected value: "<zone or node> <value>".
led_zone_config() {
    _settings="$(led_zone_settings)"
    [ -n "$_settings" ] || return 0
    echo "$_settings" | jq -Rr --slurpfile c "/mnt/SDCARD/Saves/spruce/spruce-config.json" '
        split(" ") as [$k, $t]
        | "\($t) \($c[0].menuOptions."RGB LED Settings"[$k].selected // "Default")"'
}

set_rgb_in_menu() {
    # get relevant variables from spruce-config.json
    color_name="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDcolor.selected' "Green")"
    effect="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDeffect.selected' "static")"
    duration="$(get_config_value '.menuOptions."RGB LED Settings".defaultLEDduration.selected' "1000")"

    # map color names to hex values
    color_hex="$(map_color_name_to_hex "$color_name")"

    zone_colors="$(led_zone_config | grep -v '^max_scale')"
    if [ -z "$zone_colors" ]; then
        rgb_led "lrm12b" "$effect" "$color_hex" "$duration" "-1"
        return
    fi

    default_zones="$(echo "$zone_colors" | awk '$2 == "Default" { printf "%s", $1 }')"
    [ -n "$default_zones" ] && rgb_led "$default_zones" "$effect" "$color_hex" "$duration" "-1"

    echo "$zone_colors" | while read -r zone color; do
        case "$color" in
            "Default") continue ;;
            "Off") hex=000000 ;;
            *) hex="$(map_color_name_to_hex "$color")" ;;
        esac
        rgb_led "$zone" "$effect" "$hex" "$duration" "-1"
    done
}

set_network_proxy() {
    enable_proxy="$(get_config_value '.menuOptions."Proxy Settings".enableProxy.selected' "False")"
    if [ "$enable_proxy" != "True" ]; then
        unset http_proxy https_proxy
        return 0
    fi
    proxy_protocol="$(get_config_value '.menuOptions."Proxy Settings".proxyProtocol.selected' "http")"
    proxy_address="$(get_config_value '.menuOptions."Proxy Settings".proxyAddress.selected' "")"
    proxy_port="$(get_config_value '.menuOptions."Proxy Settings".proxyPort.selected' "")"

    proxy=""

    if [ "$enable_proxy" = "True" ]; then
        if [ -n "$proxy_address" ] && [ -n "$proxy_port" ]; then
            case "$proxy_port" in
                *[!0-9]*)
                    log_message "Invalid proxy port (not a number): $proxy_port"
                    unset http_proxy https_proxy
                    return 1
                    ;;
            esac

            if [ "$proxy_port" -lt 1 ] || [ "$proxy_port" -gt 65535 ]; then
                log_message "Invalid proxy port (out of range 1-65535): $proxy_port"
                unset http_proxy https_proxy
                return 1
            fi

            proxy="${proxy_protocol}://${proxy_address}:${proxy_port}"
        fi
    fi

    if [ -n "$proxy" ]; then
        log_message "Set network proxy as $proxy"
        export http_proxy="$proxy"
        export https_proxy="$proxy"
    else
        unset http_proxy https_proxy
    fi
}

extract_7z_with_progress() {
    UPDATE_FILE="$1"
    DEST_DIR="$2"
    LOG_LOCATION="$3" # Only logs errors
    SECTION_LABEL="$4" # Optional: section title used in "Unpacking <section>"
    SUPPRESS_PROGRESS_UI="${SPRUCE_SUPPRESS_EXTRACT_PROGRESS_UI:-0}"

    if [ -z "$UPDATE_FILE" ] || [ -z "$DEST_DIR" ] || [ -z "$LOG_LOCATION" ]; then
        echo "Usage: extract_7z_with_progress <archive.7z> <destination> <log_file> [section_label]"
        return 1
    fi

    LOGO="/mnt/SDCARD/spruce/imgs/tree_sm_close_crop.png"
    if [ -z "$SECTION_LABEL" ]; then
        SECTION_LABEL="$(basename "$UPDATE_FILE" .7z)"
    fi

    if [ "${SPRUCE_FIRSTBOOT_UI:-0}" = "1" ]; then
        SECTION_TITLE="Sprucing up your device...\nUnpacking ${SECTION_LABEL}"
    else
        SECTION_TITLE="Unpacking ${SECTION_LABEL}"
    fi

    TOTAL_FILES=$(7zr l -scsUTF-8 "$UPDATE_FILE" |
        awk '$1 ~ /^[0-9][0-9][0-9][0-9]-/ { count++ } END { print count }')

    [ "$TOTAL_FILES" -eq 0 ] && TOTAL_FILES=1

    FILE_COUNT=0
    PERCENT_COMPLETE=0
    THROTTLE=10  # update UI every N files

    # Ensure destination exists
    if ! mkdir -p "$DEST_DIR"; then
        echo "Failed to create destination directory: $DEST_DIR" >>"$LOG_LOCATION"
        return 1
    fi

    if [ "$SUPPRESS_PROGRESS_UI" != "1" ]; then
        display_image_and_text "$LOGO" 35 25 "${SECTION_TITLE}\nPreparing extraction..." 75
        sleep 2
    fi

    7zr x -y -scsUTF-8 -bb1 -o"$DEST_DIR" "$UPDATE_FILE" 2>>"$LOG_LOCATION" |
    while read -r line || [ -n "$line" ]; do
        case "$line" in
            "- "*) FILE="${line#- }" ;;
            "Extracting  "*) FILE="${line#Extracting  }" ;;
            "Inflating  "*) FILE="${line#Inflating  }" ;;
            *) continue ;;
        esac
        [ -z "$FILE" ] && continue

        FILE_COUNT=$((FILE_COUNT + 1))
        PERCENT_COMPLETE=$((FILE_COUNT * 100 / TOTAL_FILES))
        [ "$PERCENT_COMPLETE" -gt 100 ] && PERCENT_COMPLETE=100

        if [ "$SUPPRESS_PROGRESS_UI" != "1" ] &&
            { [ $((FILE_COUNT % THROTTLE)) -eq 0 ] || [ "$FILE_COUNT" -eq "$TOTAL_FILES" ]; }; then
            FILE_NAME="$(basename "$FILE")"
            display_image_and_text \
                "$LOGO" \
                35 25 \
                "${SECTION_TITLE}\n${PERCENT_COMPLETE}%: ${FILE_NAME}" \
                75
        fi
    done

    RET=$?

    if [ "$RET" -ne 0 ]; then
        log_update_message "Warning: Some files may have been skipped during extraction. Check $LOG_LOCATION for details."
        if [ "$SUPPRESS_PROGRESS_UI" != "1" ]; then
            display_image_and_text "$LOGO" 35 25 \
                "Extraction completed with warnings. Check the log for details." 75
        fi
    else
        log_update_message "Extraction process completed successfully"
        if [ "$SUPPRESS_PROGRESS_UI" != "1" ]; then
            display_image_and_text "$LOGO" 35 25 "Extraction completed!" 75
        fi
    fi

    return "$RET"
}


##### SDL GAMECONTROLLER MAPPING #####

# Hand SDL a GameController mapping for the built-in pad.
#
# Nothing on BaseOS ships one. Every H700 Anbernic reports the same GUID and the
# name "ANBERNIC-keys", so SDL cannot pick a per-model mapping by itself either -
# AnbernicXXCommon.cfg selects the right one by BASEOS_TARGET and leaves it in
# SDL_GAMECONTROLLER_MAP. Without it a pad enumerates as a plain joystick with
# is_gamecontroller false, and anything driving input through SDL_GameController
# silently does nothing: PPSSPP, PICO-8, vtree and gptokeyb have all hit this.
#
# There are two forms and picking the wrong one is not a failure, it is a
# symmetric swap - A and B doing each other's job, Y doing what X should - which
# is easy to misread as a broken mapping rather than the wrong convention:
#
#   (default)     label-named. "a" is the button *marked* A. What RetroArch and
#                 PPSSPP want, since A is confirm on a Nintendo layout.
#   positional    SDL's own convention: a South, b East, x West, y North. What
#                 an app wants when it speaks raw SDL - gptokeyb's .gptk files -
#                 or when it already applies its own Nintendo correction, as
#                 vtree does with spruce's nintendo-button-labels patch.
#
# Only the four face buttons differ between the two; shoulders, triggers, stick
# clicks and the d-pad are identical. Safe to call anywhere: it is a no-op when
# SDL_GAMECONTROLLER_MAP is unset, which is every non-BaseOS device.
#
# Usage:
#   export_sdl_gamecontroller_map              # label-named
#   export_sdl_gamecontroller_map positional   # SDL convention
export_sdl_gamecontroller_map() {
    [ -n "$SDL_GAMECONTROLLER_MAP" ] || return 0

    case "$1" in
        positional)
            SDL_GAMECONTROLLERCONFIG="$(printf '%s' "$SDL_GAMECONTROLLER_MAP" \
                | sed -e 's/a:\([^,]*\),b:\([^,]*\)/a:\2,b:\1/' \
                      -e 's/x:\([^,]*\),y:\([^,]*\)/x:\2,y:\1/')"
            ;;
        *)
            SDL_GAMECONTROLLERCONFIG="$SDL_GAMECONTROLLER_MAP"
            ;;
    esac

    export SDL_GAMECONTROLLERCONFIG
}

##### WIFI HANDLING #####

# Merge the network blocks of another wpa_supplicant.conf into ours, skipping
# any SSID we already have. Used when taking the radio over from whatever
# brought it up before us.
#
# Nothing here may log block contents: they hold pre-shared keys in the clear.
# Only counts and paths are logged.
import_wpa_networks_from() {
    FOREIGN_CONF="$1"

    [ -n "$FOREIGN_CONF" ] || return 0
    [ -f "$FOREIGN_CONF" ] || return 0
    [ -n "$WPA_SUPPLICANT_FILE" ] || return 0
    [ "$FOREIGN_CONF" = "$WPA_SUPPLICANT_FILE" ] && return 0

    TMP_IMPORT="/tmp/wpa_import.$$"
    awk -v ours="$WPA_SUPPLICANT_FILE" '
        BEGIN {
            while ((getline line < ours) > 0) {
                if (line ~ /^[ \t]*ssid=/) {
                    sub(/^[ \t]*ssid=/, "", line)
                    have[line] = 1
                }
            }
            close(ours)
        }
        # No brace in either regex: busybox awk parses an unescaped { as the
        # start of an interval expression and rejects the whole pattern with
        # "Invalid contents of {}". Matching "network=" is enough to open a
        # block, and $1 == "}" closes one whatever the indentation.
        /^[ \t]*network[ \t]*=/ { inblock = 1; n = 0; ssid = "" }
        inblock {
            buf[n++] = $0
            if ($0 ~ /^[ \t]*ssid=/) { ssid = $0; sub(/^[ \t]*ssid=/, "", ssid) }
            if ($1 == "}") {
                inblock = 0
                if (ssid != "" && !(ssid in have)) {
                    have[ssid] = 1
                    printf "\n"
                    for (i = 0; i < n; i++) print buf[i]
                }
            }
        }
    ' "$FOREIGN_CONF" > "$TMP_IMPORT" 2>/dev/null

    NEW_COUNT=$(grep -c '^[[:space:]]*network[[:space:]]*=' "$TMP_IMPORT" 2>/dev/null)
    if [ "${NEW_COUNT:-0}" -gt 0 ]; then
        cat "$TMP_IMPORT" >> "$WPA_SUPPLICANT_FILE"
        log_message "Imported $NEW_COUNT network(s) from $FOREIGN_CONF"
    else
        log_message "No new networks to import from $FOREIGN_CONF"
    fi
    rm -f "$TMP_IMPORT"
}



# Does this device have a WiFi radio at all? A STATIC hardware question,
# deliberately separate from device_wifi_is_available: that older hook answers
# a LIVE question on some devices (the Pixel2 returns false whenever wlan0 is
# not up yet - correct for check_and_connect_wifi's "is there a network right
# now", and exactly wrong for deciding whether to bring the radio up, since
# enable_wifi is what puts the interface up in the first place). Only a device
# whose radio genuinely does not work answers device_has_wifi_radio false
# (today: the RG28XX, SPR-MED-177); everywhere else - including platforms that
# never define it - the answer is yes and nothing changes. The system json's
# "wifi" flag is the USER's preference and is only consulted once the hardware
# is there.
wifi_available_on_device() {
    if command -v device_has_wifi_radio >/dev/null 2>&1; then
        device_has_wifi_radio
    else
        return 0
    fi
}

# Every radio change goes through wifi.sh, which runs them one at a time.
# See wifi.sh for the commands; they return at once unless given --wait.
wifi_request() {
    sh /mnt/SDCARD/spruce/scripts/network/wifi.sh "$@"
}

# Is the saved WiFi setting on? PyUI writes SYSTEM_JSON from its shipped default,
# and on a first boot it may not exist yet, so read that default instead. With
# neither readable it means off.
wifi_setting_wanted() {
    _wifi_want="$(jq -r '.wifi // 0' "$SYSTEM_JSON" 2>/dev/null)"
    if [ -z "$_wifi_want" ] && [ -n "$SYSTEM_JSON_DEFAULT" ]; then
        _wifi_want="$(jq -r '.wifi // 0' "$SYSTEM_JSON_DEFAULT" 2>/dev/null)"
    fi
    [ "$_wifi_want" = 1 ]
}

bluetooth_setting_wanted() {
    [ "$(jq -r '.bluetooth // 0' "$SYSTEM_JSON" 2>/dev/null)" = 1 ]
}

# A hidden network never shows in a scan, so one saved counts as in range.
saved_wifi_in_range() {
    grep -q '^[[:space:]]*scan_ssid=1' "$WPA_SUPPLICANT_FILE" 2>/dev/null && return 0
    _swr_saved=/tmp/wifi_saved_ssids.$$
    /mnt/SDCARD/spruce/scripts/network/wifi.sh saved > "$_swr_saved" 2>/dev/null
    if [ ! -s "$_swr_saved" ]; then
        rm -f "$_swr_saved"
        return 1
    fi
    /mnt/SDCARD/spruce/scripts/network/wifi.sh scan 2>/dev/null | cut -f1 | grep -qxFf "$_swr_saved"
    _swr_rc=$?
    rm -f "$_swr_saved"
    return "$_swr_rc"
}

# Print why a wpa_supplicant.conf is unusable, or nothing if it is fine.
# Conservative on purpose: a false positive costs the user every saved network.
# No quote checks - wpa_supplicant takes everything between the first and last
# quote verbatim, so ssid="my"net" is valid.
wpa_conf_problem() {
    if ! grep -q '[^[:space:]]' "$1" 2>/dev/null; then
        echo "file is empty"
        return
    fi
    if ! grep -q 'ctrl_interface' "$1" 2>/dev/null; then
        echo "no ctrl_interface line, so wpa_cli would have no socket to talk to"
        return
    fi
    # No brace in a regex: busybox awk rejects an unescaped { there
    awk '
        { line = $0; gsub(/^[ \t\r]+|[ \t\r]+$/, "", line) }
        line == "" || substr(line, 1, 1) == "#" { next }
        substr(line, 1, 9) == "network={" { depth++; next }
        line == "}" {
            depth--
            if (depth < 0) { print "stray closing brace on line " NR; bad = 1; exit }
        }
        END { if (!bad && depth != 0) print "a network block is never closed" }
    ' "$1"
}

# Make sure WPA_SUPPLICANT_FILE exists and parses. A broken one is moved aside,
# not deleted: the networks are the user's and the file shows what went wrong.
wpa_conf_ensure() {
    [ -n "$WPA_SUPPLICANT_FILE" ] || return 0
    if [ -f "$WPA_SUPPLICANT_FILE" ]; then
        _wpa_problem="$(wpa_conf_problem "$WPA_SUPPLICANT_FILE")"
        [ -n "$_wpa_problem" ] || return 0
        if ! mv -f "$WPA_SUPPLICANT_FILE" "$WPA_SUPPLICANT_FILE.broken" 2>/dev/null; then
            log_message "wpa_supplicant.conf is broken ($_wpa_problem) and could not be moved aside"
            return 1
        fi
        log_message "wpa_supplicant.conf could not be parsed ($_wpa_problem); kept it as wpa_supplicant.conf.broken and started a fresh one. Saved networks will need re-entering."
    else
        mkdir -p "$(dirname "$WPA_SUPPLICANT_FILE")" 2>/dev/null
        log_message "Created missing $WPA_SUPPLICANT_FILE"
    fi
    printf 'ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n\n' > "$WPA_SUPPLICANT_FILE"
}

# Replace any saved block for SSID $1 with a new one; $2 is the password, empty
# for an open network. The password only ever goes through printf, a shell
# builtin, so it never shows up in a process list or the log.
#
# wpa_conf_save_network only edits the card's conf, which is what makes a
# password travel with the card. Devices whose own OS runs the radio (dArkMoss)
# call it alone; the rest go through wpa_add_network, which also points the
# running supplicant at the new block.
wpa_conf_save_network() {
    [ -n "$WPA_SUPPLICANT_FILE" ] && [ -n "$1" ] || return 1
    wpa_conf_ensure
    _wpa_tmp="$WPA_SUPPLICANT_FILE.tmp"
    WPA_ADD_SSID="$1" awk '
        BEGIN { want = "ssid=\"" ENVIRON["WPA_ADD_SSID"] "\"" }
        { line = $0; gsub(/^[ \t\r]+|[ \t\r]+$/, "", line) }
        !inblock && substr(line, 1, 8) == "network=" { inblock = 1; n = 0; drop = 0 }
        inblock {
            buf[n++] = $0
            if (line == want) drop = 1
            if (line == "}") {
                inblock = 0
                if (!drop) for (i = 0; i < n; i++) print buf[i]
            }
            next
        }
        { print }
        END { if (inblock) for (i = 0; i < n; i++) print buf[i] }
    ' "$WPA_SUPPLICANT_FILE" > "$_wpa_tmp" 2>/dev/null || { rm -f "$_wpa_tmp"; return 1; }
    {
        printf '\nnetwork={\n'
        printf '    ssid="%s"\n' "$1"
        if [ -n "$2" ]; then
            printf '    psk="%s"\n' "$2"
        else
            printf '    key_mgmt=NONE\n'
        fi
        printf '}\n'
    } >> "$_wpa_tmp"
    mv -f "$_wpa_tmp" "$WPA_SUPPLICANT_FILE" || { rm -f "$_wpa_tmp"; return 1; }
    return 0
}

wpa_add_network() {
    wpa_conf_save_network "$1" "$2" || return 1
    wpa_cli -i wlan0 reconfigure >/dev/null 2>&1
    return 0
}

# Print the card's saved networks as "ssid<TAB>password" lines, password empty
# for an open network, quotes stripped. For hosts that keep their own store and
# need to be told what the card knows.
wpa_conf_list_networks() {
    [ -n "$WPA_SUPPLICANT_FILE" ] && [ -f "$WPA_SUPPLICANT_FILE" ] || return 0
    awk '
        function unquote(v) { sub(/^"/, "", v); sub(/"$/, "", v); return v }
        { line = $0; gsub(/^[ \t\r]+|[ \t\r]+$/, "", line) }
        substr(line, 1, 8) == "network=" { inblock = 1; ssid = ""; psk = ""; next }
        !inblock { next }
        substr(line, 1, 5) == "ssid=" { ssid = unquote(substr(line, 6)) }
        substr(line, 1, 4) == "psk=" { psk = unquote(substr(line, 5)) }
        line == "}" { inblock = 0; if (ssid != "") printf "%s\t%s\n", ssid, psk }
    ' "$WPA_SUPPLICANT_FILE"
}

wpa_forget_all_networks() {
    _wpa_header="ctrl_interface=DIR=/var/run/wpa_supplicant
update_config=1"

    if command -v nmcli >/dev/null 2>&1 && { device_manages_own_wifi || [ -z "$WPA_SUPPLICANT_FILE" ]; }; then
        # NetworkManager keeps its own profiles. Match on TYPE: an inactive
        # profile has no DEVICE. The card's conf is cleared below as well, or
        # the next boot would import every network straight back.
        nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r uuid type; do
            [ "$type" = "802-11-wireless" ] && nmcli connection delete uuid "$uuid" >/dev/null 2>&1
        done
    elif [ -n "$WPA_SUPPLICANT_FILE" ]; then
        killall wpa_supplicant 2>/dev/null
        device_stop_dhcp_client
        sleep 1
    fi
    [ -n "$WPA_SUPPLICANT_FILE" ] || return 0

    printf '%s\n' "$_wpa_header" > "$WPA_SUPPLICANT_FILE"

    # And from the pre-card-global locations, or enable_wifi's adoption sweep
    # would import every one of them straight back on the next boot and the
    # user's "forget all networks" would silently undo itself.
    for _legacy_conf in $WPA_LEGACY_CONFS; do
        [ -f "$_legacy_conf" ] || continue
        printf '%s\n' "$_wpa_header" > "$_legacy_conf"
        log_message "Wifi: cleared saved networks from $_legacy_conf"
    done
}

# NetworkManager boards: join $1 (SSID; $2 password, empty for an open network) within 45 s. nmcli's output can echo
# the password, so only its exit status and a fixed phrase are logged. A profile for the SSID goes first (NM 1.52).
nm_wifi_connect() {
    command -v nmcli >/dev/null 2>&1 || { log_message "nm_wifi_connect: no nmcli"; return 1; }
    nmcli -t -f UUID,TYPE connection show 2>/dev/null | while IFS=: read -r _uuid _type; do
        [ "$_type" = "802-11-wireless" ] || continue
        [ "$(nmcli -g 802-11-wireless.ssid connection show uuid "$_uuid" 2>/dev/null)" = "$1" ] || continue
        nmcli connection delete uuid "$_uuid" >/dev/null 2>&1
    done
    if [ -n "$2" ]; then
        _nm_err="$(nmcli -w 45 device wifi connect "$1" password "$2" 2>&1 >/dev/null)"
    else
        _nm_err="$(nmcli -w 45 device wifi connect "$1" 2>&1 >/dev/null)"
    fi
    _nm_rc=$?
    [ "$_nm_rc" -eq 0 ] && { _nm_err=""; return 0; }
    case "$_nm_rc" in
        2) _nm_why="nmcli rejected the arguments" ;;
        3) _nm_why="timed out after 45 s" ;;
        4) _nm_why="activation failed" ;;
        8) _nm_why="NetworkManager is not running" ;;
        10) _nm_why="no such network or Wi-Fi device" ;;
        *) _nm_why="error" ;;
    esac
    case "$_nm_err" in
        *"ecrets were required"*) _nm_why="$_nm_why, secrets were required (wrong password?)" ;;
        *"No network with SSID"*) _nm_why="$_nm_why, the network is not in range" ;;
        *"No Wi-Fi device found"*) _nm_why="$_nm_why, no Wi-Fi device" ;;
        *"property is invalid"*) _nm_why="$_nm_why, a setting was rejected" ;;
    esac
    _nm_err=""
    log_message "nm_wifi_connect: nmcli exit $_nm_rc ($_nm_why)"
    return "$_nm_rc"
}

# Give NetworkManager every network the card's wpa_supplicant.conf holds that it lacks: its own profiles live on the
# base, so a reflash starts with none. $1 = the interface. Profiles take the SSID's name, as "device wifi connect" does.
nm_import_card_networks() {
    command -v nmcli >/dev/null 2>&1 || return 0
    _known="$(nmcli -t -f NAME connection show 2>/dev/null | sed 's/\\:/:/g')"
    wpa_conf_list_networks | while IFS="$(printf '\t')" read -r _ssid _psk; do
        [ -n "$_ssid" ] || continue
        printf '%s\n' "$_known" | grep -qxF "$_ssid" && continue
        if [ -n "$_psk" ]; then
            nmcli connection add type wifi ifname "${1:-wlan0}" con-name "$_ssid" ssid "$_ssid" \
                wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$_psk" >/dev/null 2>&1
        else
            nmcli connection add type wifi ifname "${1:-wlan0}" con-name "$_ssid" ssid "$_ssid" >/dev/null 2>&1
        fi && log_message "$PLATFORM: added network $_ssid from the card"
    done
}

# Does this interface hold an address?
#
# Ask iproute2 and net-tools both, and believe either. An ifconfig-only version
# always answered "no address" on Debian, which does not ship net-tools:
# network_is_connected never returned true, networkservices.sh waited on it
# forever, and SSH, Samba, SFTPGo, syncthing and time sync were never started.
# Nothing logged an error - that loop waits indefinitely on purpose.
#
# Believing only ip would trade that for the same bug on any busybox device
# whose ip applet does not take these options, so ask both.
iface_has_address() {
    _iface="$1"

    [ -n "$_iface" ] || return 1

    if command -v ip >/dev/null 2>&1; then
        if ip -o addr show dev "$_iface" 2>/dev/null | grep -q "inet"; then
            return 0
        fi
    fi

    if command -v ifconfig >/dev/null 2>&1; then
        if ifconfig "$_iface" 2>/dev/null | grep -qE "inet |inet6 "; then
            return 0
        fi
    fi

    return 1
}

network_is_connected() {
    CHECK_ETH="${1:-false}" # Defaults to false if no argument

	iface_up=false
    wifi_iface=$(ls /sys/class/net/ | grep wlan | head -1)

    if iface_has_address "$wifi_iface"; then
        iface_up=true
    fi

    if [ "$CHECK_ETH" = true ]; then
        if iface_has_address eth0; then
            iface_up=true
        fi
    fi

	if $iface_up; then
		if internet_reachable; then
			return 0 # Success
        fi
	fi

	return 1 # No network connection
}

# Returns 0 once connected, 1 when not (START, timeout, WiFi or waiting off).
# --cancellable also offers B on the wait screen, which returns 2: a game launch
# uses it to go back to the menu, so a player out of range can pick another network.
check_and_connect_wifi() {
    # Shutdown's Syncthing check calls this whatever the setting says; never turn WiFi on against it
    if ! wifi_setting_wanted; then
        log_message "WiFi is off in settings, not connecting"
        return 1
    fi

    if network_is_connected true; then
        log_message "Active network connection verified"
        return 0
    fi

    waiting_enabled="$(get_config_value '.menuOptions."Network Settings".enableWaitingToConnect.selected' "True")"
    if [ "$waiting_enabled" = "False" ]; then
        log_message "User opted out of waiting to connect, via spruce network settings."
        return 1
    fi

    timeout=60
    start_time=$(date +%s)

    # Check if device has wifi available
    if ! device_wifi_is_available; then
        return 1
    fi

    log_message "Attempting to connect to WiFi"
    start_pyui_message_writer 1
    wifi_request restart

    cancel_key=""
    wait_text="Waiting to connect....\nPress START to continue anyway."
    if [ "$1" = "--cancellable" ] && [ -n "$B_B" ]; then
        cancel_key="$B_B"
        wait_text="Waiting to connect....\nPress START to continue anyway, or B to go back."
    fi
    display_image_and_text "/mnt/SDCARD/spruce/imgs/signal.png" 35 20 "$wait_text" 75

    rm -f /tmp/ge_out 2>/dev/null

    # Start getevent in background
    getevent "$EVENT_PATH_READ_INPUTS_SPRUCE" > /tmp/ge_out &
    GE_PID=$!

    while true; do
        # 1. Check for user input
        if line=$(last_key_line /tmp/ge_out "$B_START" "$B_START_2" "$cancel_key"); then
            case "$line" in
                *"key $B_START"* | *"key $B_START_2"*)
                    log_message "WiFi connection cancelled by user"
                    kill "$GE_PID" 2>/dev/null
                    display_image_and_text "/mnt/SDCARD/spruce/imgs/notfound.png" 35 25 \
                        "Proceeding before connected to wifi." 75
                    sleep 2
                    stop_pyui_message_writer
                    return 1
                    ;;
                *"key $B_B"*)
                    # Only asked for with --cancellable
                    log_message "WiFi wait left with B"
                    kill "$GE_PID" 2>/dev/null
                    stop_pyui_message_writer
                    return 2
                    ;;
            esac
        fi

        # 2. Check for successful connection
        if network_is_connected; then
            log_message "Successfully connected to WiFi"
            kill "$GE_PID" 2>/dev/null
            stop_pyui_message_writer
            return 0
        fi

        # 3. Check for timeout
        current_time=$(date +%s)
        if [ $((current_time - start_time)) -ge $timeout ]; then
            log_message "WiFi connection timed out after $timeout seconds"
            kill "$GE_PID" 2>/dev/null
            stop_pyui_message_writer
            return 1
        fi

        sleep 0.1
    done
    stop_pyui_message_writer
}

##### ACTIVITY TRACKER STUFF #####

get_current_app() {
    if [ -f /tmp/cmd_to_run.sh ]; then
        sed 's/[[:space:]]*$//' /tmp/cmd_to_run.sh
    else
        printf 'PyUI\n'
    fi
}

extract_entry_name() {
    cmd="$1"

    case "$cmd" in
        *emu/standard_launch.sh*)
            # Get last quoted argument
            last_arg=$(printf '%s\n' "$cmd" \
                | sed -n 's/.*"\([^"]*\)"/\1/p' \
                | tail -n 1)
            # Extract everything after the last "Roms/"
            if echo "$last_arg" | grep -q "Roms/"; then
                rom_path=$(printf '%s\n' "$last_arg" | sed 's/.*\(Roms\/.*\)/\1/')
                # Remove any trailing quote
                rom_path="${rom_path%\"}"
                printf '%s\n' "$rom_path"
            else
                printf '%s\n' "${last_arg##*/}"
            fi
            ;;
        *App/*)
            # Extract everything after the LAST "App/" including subfolders and file
            app_path=$(printf '%s\n' "$cmd" \
                | sed -n 's/.*\(App\/.*\)/\1/p' \
                | tail -n 1)
            # Remove any trailing quote
            app_path="${app_path%\"}"
            printf '%s\n' "$app_path"
            ;;
        *)
            printf '%s\n' "$cmd"
            ;;
    esac
}


log_activity_event() {
    app="$1"
    event="$2"

    [ -z "$app" ] && return 1
    [ -z "$event" ] && return 1

    ts="$(date +%s)"
    pid="$$"

    LOG_DIR="/mnt/SDCARD/Saves/spruce"
    LOG_FILE="$LOG_DIR/activity.jsonl"

    mkdir -p "$LOG_DIR" || return 1

    name=$(extract_entry_name "$app")

    safe_app=$(printf '%s' "$name" | sed '
        s/\\/\\\\/g
        s/"/\\"/g
        s/\t/\\t/g
        s/\r/\\r/g
        s/\n/\\n/g
    ')

    printf '{"ts":%s,"event":"%s","app":"%s","pid":%s}\n' \
        "$ts" "$event" "$safe_app" "$pid" >> "$LOG_FILE"
}

SPRUCE_HELPERS_LOADED=$$
