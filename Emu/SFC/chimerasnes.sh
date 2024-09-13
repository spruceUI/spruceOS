#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is mednafen_supafaust"|"name": "Change core to mednafen_supafaust"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is snes9x"|"name": "Change core to snes9x"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is snes9x2005"|"name": "Change core to snes9x2005"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is chimerasnes"|"name": "Change core to chimerasnes"|g' "$CONFIG"
        sed -i 's|"name": "Change core to chimerasnes"|"name": "✓ Core is chimerasnes"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"chimerasnes\"/g' "$SYS_OPT"
