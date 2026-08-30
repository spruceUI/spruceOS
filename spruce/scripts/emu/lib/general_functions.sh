#!/bin/sh

# Requires:
#   EMU_NAME, EMU_JSON_PATH, GAME
#   CORE, MODE, EMU_CPUS (globals set/used by functions)
#   log_message, set_overclock, pin_cpu
#   jq, pgrep, sleep
#   /mnt/SDCARD/spruce/scripts/enforceSmartCPU.sh
#
# Provides:
#   get_effective_ra_build
#   set_emu_core_from_emu_json
#   get_cpu_mode_from_emu_json
#   use_default_emulator
#   get_core_override
#   get_mode_override
#   set_cpu_mode
#   pin_to_dedicated_cores
#   emu_log_file


# Returns the log file path for standalone emulators.
# When verbose_emulators flag is not set, returns /dev/null.
emu_log_file() {
	if [ "$VERBOSE_EMU" = "1" ]; then
		echo "${LOG_DIR}/${CORE}-${PLATFORM}.log"
	else
		echo "/dev/null"
	fi
}

get_effective_ra_build() {
    # raBuild selection only applies to devices with both 32-bit and 64-bit universal RA
    [ "$DEVICE_HAS_32_BIT_RA" = "true" ] || return
    ra_build="$(jq -r --arg game "$GAME" \
        '.menuOptions.raBuild.overrides[$game] // .menuOptions.raBuild.selected // empty' \
        "$EMU_JSON_PATH" 2>/dev/null)"
    echo "$ra_build"
}

# The Emulator* menuOption key whose "devices" list names this device, resolved
# exactly the way PyUI's Device.get_selected_emulator does: walk the keys in
# file order and take the first whose list contains any of our names. Empty when
# nothing matches, so callers fall through to their existing behaviour.
emu_option_key_for_device() {
    _names="$(device_names 2>/dev/null)"
    [ -n "$_names" ] || return 0
    _names_json="$(printf '%s\n' $_names | jq -R . | jq -sc .)"
    jq -r --argjson names "$_names_json" '
        [ .menuOptions | to_entries[]
          | select(.key | startswith("Emulator"))
          | select( [ (.value.devices // [])[] as $d | $names | index($d) ]
                    | map(select(. != null)) | length > 0 )
        ][0].key // empty
    ' "$EMU_JSON_PATH" 2>/dev/null
}

set_emu_core_from_emu_json() {
    # Try to use platform-specific emulator if it exists
    CORE_PATH=".menuOptions.Emulator_$PLATFORM.selected"
    if jq -e "$CORE_PATH" "$EMU_JSON_PATH" >/dev/null 2>&1; then
        export CORE="$(jq -r "$CORE_PATH" "$EMU_JSON_PATH")"
        return
    fi

    # Match the "devices" list the way PyUI does, before falling back on the
    # architecture suffix. Without this the Anbernic XX line never resolved:
    # PyUI writes the choice into Emulator_Flip (matched by the ANBERNIC_RGXX
    # family token) while this looked for Emulator_AnbernicXX640480, found
    # nothing, and silently used default_emulator - so every non-default
    # emulator choice on that line was discarded.
    DEV_KEY="$(emu_option_key_for_device)"
    if [ -n "$DEV_KEY" ]; then
        CORE_SEL="$(jq -r --arg k "$DEV_KEY" '.menuOptions[$k].selected // empty' "$EMU_JSON_PATH" 2>/dev/null)"
        if [ -n "$CORE_SEL" ] && [ "$CORE_SEL" != "null" ]; then
            export CORE="$CORE_SEL"
            return
        fi
    fi

    # Try the architecture suffix
    ARCH_SUFFIX="64"
    [ "$PLATFORM_ARCHITECTURE" = "armhf" ] && ARCH_SUFFIX="32"
    # Override if raBuild is set to 32-bit (per-game or system-wide)
    [ "$RA_BUILD" = "32-bit" ] && ARCH_SUFFIX="32"
    CORE_PATH=".menuOptions.Emulator_$ARCH_SUFFIX.selected"
    if jq -e "$CORE_PATH" "$EMU_JSON_PATH" >/dev/null 2>&1; then
        export CORE="$(jq -r "$CORE_PATH" "$EMU_JSON_PATH")"
        return
    fi

    export CORE="$(jq -r '.menuOptions.Emulator.selected' "$EMU_JSON_PATH")"
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
    elif [ -n "$(emu_option_key_for_device)" ]; then
        # Same devices-list resolution, so a per-game override is read from the
        # key the UI actually wrote it to. The NDS arm below sent every non-Flip
        # device to Emulator_Brick, which on the XX line holds nothing.
        core_section=".menuOptions.$(emu_option_key_for_device)"
    else
        # Fallback for EMU_NAME-specific keys
        case "$EMU_NAME" in
            ARCADE|DC|NAOMI|N64|PS)
                if [ "$PLATFORM" = "A30" ]; then
                    core_section=".menuOptions.Emulator_A30"
                elif [ "$RA_BUILD" = "32-bit" ] && jq -e '.menuOptions.Emulator_32' "$EMU_JSON_PATH" >/dev/null 2>&1; then
                    core_section=".menuOptions.Emulator_32"
                else
                    core_section=".menuOptions.Emulator_64"
                fi
                ;;
            MEDIA)
                ARCH_SUFFIX="64"
                [ "$PLATFORM_ARCHITECTURE" = "armhf" ] && ARCH_SUFFIX="32"
                core_section=".menuOptions.Emulator_$ARCH_SUFFIX"
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