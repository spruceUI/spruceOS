#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is fceumm"|"name": "Change core to fceumm"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is nestopia"|"name": "Change core to nestopia"|g' "$CONFIG"
        sed -i 's|"name": "Change core to nestopia"|"name": "✓ Core is nestopia"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"nestopia\"/g' "$SYS_OPT"