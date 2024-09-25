#!/bin/sh

EMU_DIR="$(echo "$1" | cut -d'/' -f5)"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is mednafen_ngp"|"name": "Change core to mednafen_ngp"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is race"|"name": "Change core to race"|g' "$CONFIG"
        sed -i 's|"name": "Change core to race"|"name": "✓ Core is race"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"race\"/g' "$SYS_OPT"