#!/bin/sh

# Requires:
#   EMU_NAME, EMU_JSON_PATH, GAME
#   CORE, MODE, EMU_CPUS (globals set/used by functions)
#   log_message, set_overclock, pin_cpu
#   jq, pgrep, sleep
#   /mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh
#
# Provides:
#   set_emu_core_from_emu_json
#   get_cpu_mode_from_emu_json
#   use_default_emulator
#   get_core_override
#   get_mode_override
#   set_cpu_mode
#   pin_to_dedicated_cores

set_emu_core_from_emu_json() {
    # Try to use platform-specific emulator if it exists
    CORE_PATH=".menuOptions.Emulator_$PLATFORM.selected"
    if jq -e "$CORE_PATH" "$EMU_JSON_PATH" >/dev/null 2>&1; then
        export CORE="$(jq -r "$CORE_PATH" "$EMU_JSON_PATH")"
        return
    fi

    case "$EMU_NAME" in
        DC|NAOMI|N64|PS)
            case "$PLATFORM" in
                "A30")    export CORE="$(jq -r '.menuOptions.Emulator_A30.selected' "$EMU_JSON_PATH")" ;;
                *)        export CORE="$(jq -r '.menuOptions.Emulator_64.selected' "$EMU_JSON_PATH")" ;;
            esac
            ;;
        NDS)
            case "$PLATFORM" in
                "Flip")	  export CORE="$(jq -r '.menuOptions.Emulator_Flip.selected' "$EMU_JSON_PATH")"  ;;
                "Brick")  export CORE="$(jq -r '.menuOptions.Emulator_Brick.selected' "$EMU_JSON_PATH")" ;;
            esac
            ;;
        *)
            export CORE="$(jq -r '.menuOptions.Emulator.selected' "$EMU_JSON_PATH")"
            ;;
    esac
}

get_cpu_mode_from_emu_json() {
    GOV="$(jq -r '.menuOptions.Governor.selected' "$EMU_JSON_PATH")"
    echo "$GOV"
}

use_default_emulator() {
	export CORE="$(jq -r '.default_emulator' "$EMU_JSON_PATH")"
	log_message "Using default core of $CORE to run $EMU_NAME"
}

get_core_override() {
    # Determine the platform-specific key first
    if jq -e ".menuOptions.Emulator_$PLATFORM" "$EMU_JSON_PATH" >/dev/null 2>&1; then
        core_section=".menuOptions.Emulator_$PLATFORM"
    else
        # Fallback for EMU_NAME-specific keys
        case "$EMU_NAME" in
            DC|NAOMI|N64|PS)
                if [ "$PLATFORM" = "A30" ]; then
                    core_section=".menuOptions.Emulator_A30"
                else
                    core_section=".menuOptions.Emulator_64"
                fi
                ;;
            NDS)
                if [ "$PLATFORM" = "Flip" ]; then
                    core_section=".menuOptions.Emulator_Flip"
                else
                    core_section=".menuOptions.Emulator_Brick"
                fi
                ;;
            *)
                core_section=".menuOptions.Emulator"
                ;;
        esac
    fi

    # 1) Check per-game override in the resolved section
    core_override=$(jq -r --arg game "$GAME" "$core_section.overrides[\$game]" "$EMU_JSON_PATH")
    if [ -n "$core_override" ] && [ "$core_override" != "null" ]; then
        export CORE="$core_override"
        return
    fi

    # 2) Fallback to the section's selected core
    core_override=$(jq -r "$core_section.selected" "$EMU_JSON_PATH")
    if [ -n "$core_override" ] && [ "$core_override" != "null" ]; then
        export CORE="$core_override"
    fi
}


get_mode_override() {
	local mode_override="$(jq -r --arg game "$GAME" '.menuOptions.Governor.overrides[$game]' "$EMU_JSON_PATH")"
	if [ -n "$mode_override" ] && [ "$mode_override" != "null" ]; then
		export MODE=$mode_override
	fi
}

set_cpu_mode() {
    log_message "Setting CPU mode to $MODE"
	if [ "$MODE" = "Overclock" ]; then
		if [ "$EMU_NAME" = "NDS" ]; then
			( sleep 33 && set_overclock ) &
		else
            log_message "Applying overclock mode"
			set_overclock
		fi
	elif [ "$MODE" = "Powersave" ]; then
        set_powersave
	elif [ "$MODE" = "Performance" ]; then
        set_performance
    else
        log_message "Calling enforceSmartCPU"
		smart_freq="$(jq -r '.scaling_min_freq' "$EMU_JSON_PATH")"
		/mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh "$smart_freq" &
	fi
}

pin_to_dedicated_cores() {
	comm="$1"
	delay="$2:-1"

    # get the last two cores that are online
    EMU_CPUS=${DEVICE_MAX_CORES_ONLINE#${DEVICE_MAX_CORES_ONLINE%??}}
    {
        sleep "$delay"
        pgrep "$comm" | while read -r pid; do
            pin_cpu "$EMU_CPUS" -p "$pid"
        done
    } &
}