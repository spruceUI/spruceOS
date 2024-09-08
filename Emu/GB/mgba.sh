#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is gambatte"|"name": "Change core to gambatte"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is mgba"|"name": "Change core to mgba"|g' "$CONFIG"
        sed -i 's|"name": "Change core to mgba"|"name": "✓ Core is mgba"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"mgba\"/g' "$SYS_OPT"
