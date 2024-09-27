#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is gpsp"|"name": "Change core to gpsp"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is mgba"|"name": "Change core to mgba"|g' "$CONFIG"
        sed -i 's|"name": "Change core to gpsp"|"name": "✓ Core is gpsp"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"gpsp\"/g' "$SYS_OPT"
