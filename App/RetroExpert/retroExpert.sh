#!/bin/sh

APP_DIR="/mnt/SDCARD/App/RetroExpert"
IMAGE_PATH="$APP_DIR/imgs/switching.png"
CONFIG_FILE="$APP_DIR/config.json"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# Add a new parameter for silent mode
SILENT_MODE=${1:-false}

if [ "$SILENT_MODE" != "true" ] && [ ! -f "$IMAGE_PATH" ]; then
    log_message "Image file not found at $IMAGE_PATH"
    exit 1
fi

if [ "$SILENT_MODE" != "true" ]; then
    show_image "$IMAGE_PATH"
fi

EMU_PATH="/mnt/SDCARD/Emu"
FULL_RA='RA_BIN=\"retroarch\"'
MIYOO_RA='RA_BIN=\"ra32.miyoo\"'

ORIGINAL_PROFILE_DIR="/mnt/SDCARD/RetroArch/originalProfile"
CURRENT_CFG="/mnt/SDCARD/RetroArch/retroarch.cfg"

# Check if expertRA flag exists
if flag_check "expertRA"; then
    # Switch to Miyoo RA (Normal mode)
    NEW_RA="$MIYOO_RA"
    NEW_MODE="normal"
    OLD_MODE="expert"
    sed -i 's|- On|- Off|' "$CONFIG_FILE"
    log_message "Config file updated to OFF mode"
    flag_remove "expertRA"
else
    # Switch to Full RA (Expert mode)
    NEW_RA="$FULL_RA"
    NEW_MODE="expert"
    OLD_MODE="normal"
    sed -i 's|- Off|- On|' "$CONFIG_FILE"
    log_message "Config file updated to ON mode"
    flag_add "expertRA"
fi

# Function to swap RetroArch configuration
swap_retroarch_config() {



    # Check if current config is problematic
    if grep -q 'input_fps_toggle = "backspace"' "$CURRENT_CFG" && \
       grep -q 'input_exit_emulator = "nul"' "$CURRENT_CFG" && \
       grep -q 'input_load_state = "alt"' "$CURRENT_CFG"; then
        log_message "Detected problematic config. Using fresh configuration."
        USE_FRESH_CONFIG=true
    else
        USE_FRESH_CONFIG=false
    fi
    
    # Create originalProfile directory if it doesn't exist
    if [ ! -d "$ORIGINAL_PROFILE_DIR" ]; then
        mkdir -p "$ORIGINAL_PROFILE_DIR"
        log_message "Created originalProfile directory"
    fi


    if [ "$NEW_MODE" = "expert" ] && [ "$USE_FRESH_CONFIG" = false ]; then
        # Check if current config is already expert
        if grep -q 'input_enable_hotkey = "escape"' "$CURRENT_CFG" && \
           grep -q 'input_exit_emulator = "enter"' "$CURRENT_CFG"; then
            log_message "Current config is already in expert mode. Keeping it."
            return
        fi
    fi

    # Save current config as old mode only if it's not problematic
    if [ "$USE_FRESH_CONFIG" = false ]; then
        cp "$CURRENT_CFG" "$ORIGINAL_PROFILE_DIR/retroarch-$OLD_MODE.cfg"
        log_message "Saved current config as $OLD_MODE profile"
    fi

    if [ "$USE_FRESH_CONFIG" = false ] && [ -f "$ORIGINAL_PROFILE_DIR/retroarch-$NEW_MODE.cfg" ]; then
        # Use existing profile
        cp "$ORIGINAL_PROFILE_DIR/retroarch-$NEW_MODE.cfg" "$CURRENT_CFG"
        log_message "Using existing $NEW_MODE profile"
        
        # Delete the profile after using it
        rm "$ORIGINAL_PROFILE_DIR/retroarch-$NEW_MODE.cfg"
        log_message "Deleted $NEW_MODE profile after use"
    else
        # Copy profile from hotkey or nohotkey folder
        if [ "$NEW_MODE" = "expert" ]; then
            cp "/mnt/SDCARD/RetroArch/hotkeyprofile/retroarch.cfg" "$CURRENT_CFG"
        else
            cp "/mnt/SDCARD/RetroArch/nohotkeyprofile/retroarch.cfg" "$CURRENT_CFG"
        fi
        log_message "Copied fresh $NEW_MODE profile"
    fi
}

# Call the function to swap configs
swap_retroarch_config

# Loop through emulator directories
for emu_dir in "$EMU_PATH"/*; do
    if [ -d "$emu_dir" ]; then
        sys_opt="$emu_dir/system.opt"
        toggle_sys_opt "$sys_opt"
    fi
done

# Modify the end of the script to skip image display in silent mode
if [ "$SILENT_MODE" != "true" ]; then
    kill_images
fi

