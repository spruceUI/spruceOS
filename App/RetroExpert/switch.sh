#!/bin/sh

IMAGE_PATH="/mnt/SDCARD/App/RetroExpert/switching.png"
CONFIG_FILE="/mnt/SDCARD/App/RetroExpert/config.json"

if [ ! -f "$IMAGE_PATH" ]; then
    echo "Image file not found at $IMAGE_PATH"
    exit 1
fi

show "$IMAGE_PATH" &

EMU_PATH="/mnt/SDCARD/Emu"
OLD_PREFIX='HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L '
NEW_PREFIX='HOME=$RA_DIR/ $RA_DIR/retroarch -v -L '

toggle_launch_sh() {
    local launch_file="$1"
    if [ -f "$launch_file" ]; then
        if grep -q "$OLD_PREFIX" "$launch_file"; then
            sed -i "s|$OLD_PREFIX|$NEW_PREFIX|g" "$launch_file"
            cp /mnt/SDCARD/RetroArch/hotkeyprofile/retroarch.cfg /mnt/SDCARD/RetroArch/retroarch.cfg
            sed -i 's|"label":"RETROARCH EXPERT MODE - OFF"|"label":"RETROARCH EXPERT MODE - ON"|g' "$CONFIG_FILE"
            echo "Config file updated to ON mode"

        elif grep -q "$NEW_PREFIX" "$launch_file"; then
            sed -i "s|$NEW_PREFIX|$OLD_PREFIX|g" "$launch_file"
            cp /mnt/SDCARD/RetroArch/nohotkeyprofile/retroarch.cfg /mnt/SDCARD/RetroArch/retroarch.cfg
            sed -i 's|"label":"RETROARCH EXPERT MODE - ON"|"label":"RETROARCH EXPERT MODE - OFF"|g' "$CONFIG_FILE"
            echo "Config file updated to OFF mode"
        else
            echo "No match found in $launch_file"
        fi
    else
        echo "Launch file not found: $launch_file"
    fi
}

for emu_dir in "$EMU_PATH"/*; do
    if [ -d "$emu_dir" ]; then
        launch_file="$emu_dir/launch.sh"
        toggle_launch_sh "$launch_file"
    fi
done

killall -9 show

