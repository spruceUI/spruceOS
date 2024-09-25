#!/bin/sh

EMU_DIR="$(echo "$1" | cut -d'/' -f5)"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is puae"|"name": "Change core to puae"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is puae2021"|"name": "Change core to puae2021"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is uae4arm"|"name": "Change core to uae4arm"|g' "$CONFIG"
        sed -i 's|"name": "Change core to uae4arm"|"name": "✓ Core is uae4arm"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"uae4arm\"/g' "$SYS_OPT"