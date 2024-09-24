#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_cpu_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ CPU is set to Smart Mode"|"name": "Set CPU to Smart Mode"|g' "$CONFIG"
        sed -i 's|"name": "✓ CPU is set to Performance Mode"|"name": "Set CPU to Performance Mode"|g' "$CONFIG"
        sed -i 's|"name": "✓ CPU is set to Overclock Mode"|"name": "Set CPU to Overclock Mode"|g' "$CONFIG"
        sed -i 's|"name": "Set CPU to Overclock Mode"|"name": "✓ CPU is set to Overclock Mode"|g' "$CONFIG"
    fi
}

update_cpu_config_name

sed -i 's/GOV=.*/GOV=\"overclock\"/g' "$SYS_OPT"
