#!/bin/sh

current_dir="$(dirname "$0")"
script_path="$current_dir/launch.sh"
config_path="$current_dir/config.json"

update_core_config_name() {
    if [ -f "$config_path" ]; then
        sed -i 's|"name": "✓ Core is mednafen_lynx"|"name": "Change core to mednafen_lynx"|g' "$config_path"
        sed -i 's|"name": "✓ Core is handy"|"name": "Change core to handy"|g' "$config_path"
        sed -i 's|"name": "Change core to handy"|"name": "✓ Core is handy"|g' "$config_path"
    fi
}

update_core_config_name

if command -v sed &> /dev/null; then
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/handy_libretro.so "$1"|g' "$script_path"
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/handy_libretro.so "$1"|g' "$script_path"
fi