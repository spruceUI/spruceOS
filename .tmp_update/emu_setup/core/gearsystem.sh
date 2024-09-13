#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is gearsystem"|"name": "Change core to gearsystem"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is picodrive"|"name": "Change core to picodrive"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is genesis_plus_gx"|"name": "Change core to genesis_plus_gx"|g' "$CONFIG"
        sed -i 's|"name": "Change core to gearsystem"|"name": "✓ Core is gearsystem"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"gearsystem\"/g' "$SYS_OPT"
