#!/bin/sh

IMAGE_PATH="/mnt/SDCARD/App/RetroExpert/switching.png"
CONFIG_FILE="/mnt/SDCARD/App/RetroExpert/config.json"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Image file not found at $IMAGE_PATH"
    exit 1
fi

show "$IMAGE_PATH" &

EMU_PATH="/mnt/SDCARD/Emu"
FULL_RA='RA_BIN=\"retroarch\"'
MIYOO_RA='RA_BIN=\"ra32.miyoo\"'


toggle_sys_opt() {
    local sys_opt="$1"
    if [ -f "$sys_opt" ]; then
        if grep -q "$MIYOO_RA" "$sys_opt"; then
            sed -i "s|$MIYOO_RA|$FULL_RA|g" "$sys_opt"
            cp /mnt/SDCARD/RetroArch/hotkeyprofile/retroarch.cfg /mnt/SDCARD/RetroArch/retroarch.cfg
            sed -i 's|OFF|ON|' "$CONFIG_FILE"
            echo "Config file updated to ON mode"

        elif grep -q "$FULL_RA" "$sys_opt"; then
            sed -i "s|$FULL_RA|$MIYOO_RA|g" "$sys_opt"
            cp /mnt/SDCARD/RetroArch/nohotkeyprofile/retroarch.cfg /mnt/SDCARD/RetroArch/retroarch.cfg
            sed -i 's|ON|OFF|' "$CONFIG_FILE"
            echo "Config file updated to OFF mode"
        else
            echo "No match found in $sys_opt"
        fi
    else
        echo "System Options not found: $sys_opt"
    fi
}

for emu_dir in "$EMU_PATH"/*; do
    if [ -d "$emu_dir" ]; then
        sys_opt="$emu_dir/system.opt"
        toggle_sys_opt "$sys_opt"
    fi
done

killall -9 show

