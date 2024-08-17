#!/bin/sh

current_dir="$(dirname "$0")"
script_path="$current_dir/launch.sh"
config_path="$current_dir/config.json"

update_core_config_name() {
    if [ -f "$config_path" ]; then
        sed -i 's|"name": "✓ Core is gearsystem"|"name": "Change core to gearsystem"|g' "$config_path"
        sed -i 's|"name": "✓ Core is picodrive"|"name": "Change core to picodrive"|g' "$config_path"
        sed -i 's|"name": "✓ Core is genesis_plus_gx"|"name": "Change core to genesis_plus_gx"|g' "$config_path"
        sed -i 's|"name": "Change core to gearsystem"|"name": "✓ Core is gearsystem"|g' "$config_path"
    fi
}

update_core_config_name

if command -v sed &> /dev/null; then
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/gearsystem_libretro.so "$1"|g' "$script_path"
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/gearsystem_libretro.so "$1"|g' "$script_path"
fi
