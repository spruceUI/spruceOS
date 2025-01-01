RETROARCH_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"
PCSX_CFG="/mnt/SDCARD/RetroArch/.retroarch/config/PCSX-ReARMed/PCSX-ReARMed.cfg"
SWANSTATION_CFG="/mnt/SDCARD/RetroArch/.retroarch/config/SwanStation/SwanStation.cfg"

if [ "$1" = "check" ]; then
    # Check if all rewind settings match the "On" configuration
    rewind_enabled=$(grep '^rewind_enable = ' "$RETROARCH_CFG" | cut -d '"' -f 2)
    rewind_key=$(grep '^input_rewind = ' "$RETROARCH_CFG" | cut -d '"' -f 2)

    if [ "$rewind_enabled" = "true" ] && \
       [ "$rewind_key" = "e" ]; then
        echo -n "on"
    else
        echo -n "off"
    fi
    return 0
fi

if [ "$1" = "hint" ]; then
    case "$2" in
        "on")
            echo -n "Hotkey+L2 Rewind can immpact performance"
            ;;
        *)
            echo -n "Replaces Slow Mo mode with Rewind"
            ;;
    esac
    return 0
fi

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

if [ "$1" = "assign" ]; then
    pcsx_rewind_present=$(grep '^rewind_enable = ' "$PCSX_CFG")
    swanstation_rewind_present=$(grep '^rewind_enable = ' "$SWANSTATION_CFG")
    case "$2" in
        "on")
            log_message "RetroArch Rewind: on"
            sed -i 's/^input_rewind = .*/input_rewind = "e"/' "$RETROARCH_CFG"
            sed -i 's/^input_toggle_slowmotion = .*/input_toggle_slowmotion = "nul"/' "$RETROARCH_CFG"
            sed -i 's/^rewind_enable = .*/rewind_enable = "true"/' "$RETROARCH_CFG"
            sed -i 's/^rewind_granularity = .*/rewind_granularity = "2"/' "$RETROARCH_CFG"
            if [ -n "$pcsx_rewind_present" ]; then
              sed -i 's/^rewind_enable = .*/rewind_enable = "false"/' "$PCSX_CFG"
            else
              printf 'rewind_enable = "false"\n' >> "$PCSX_CFG"
            fi
            if [ -n "$swanstation_rewind_present" ]; then
              sed -i 's/^rewind_enable = .*/rewind_enable = "false"/' "$SWANSTATION_CFG"
            else
              printf 'rewind_enable = "false"\n' >> "$SWANSTATION_CFG"
            fi
            ;;
        "off")
            log_message "RetroArch Rewind: off"
            sed -i 's/^input_rewind = .*/input_rewind = "nul"/' "$RETROARCH_CFG"
            sed -i 's/^input_toggle_slowmotion = .*/input_toggle_slowmotion = "e"/' "$RETROARCH_CFG"
            sed -i 's/^rewind_enable = .*/rewind_enable = "false"/' "$RETROARCH_CFG"
            sed -i '/^rewind_enable = /d' "$PCSX_CFG"
            sed -i '/^rewind_enable = /d' "$SWANSTATION_CFG"
            ;;
    esac
fi
