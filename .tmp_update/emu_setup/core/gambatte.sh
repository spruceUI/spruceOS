#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
EMU_DIR="/mnt/SDCARD/Emu/${EMU_NAME}"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is mgba"|"name": "Change core to mgba"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is gambatte"|"name": "Change core to gambatte"|g' "$CONFIG"
        sed -i 's|"name": "Change core to gambatte"|"name": "✓ Core is gambatte"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"gambatte\"/g' "$SYS_OPT"
