#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is mednafen_ngp"|"name": "Change core to mednafen_ngp"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is race"|"name": "Change core to race"|g' "$CONFIG"
        sed -i 's|"name": "Change core to mednafen_ngp"|"name": "✓ Core is mednafen_ngp"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"mednafen_ngp\"/g' "$SYS_OPT"