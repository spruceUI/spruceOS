#!/bin/sh

current_dir="$(dirname "$0")"
script_path="$current_dir/launch.sh"
config_path="$current_dir/config.json"

update_core_config_name() {
    if [ -f "$config_path" ]; then
        sed -i 's|"name": "✓ Core is mednafen_ngp"|"name": "Change core to mednafen_ngp"|g' "$config_path"
        sed -i 's|"name": "✓ Core is race"|"name": "Change core to race"|g' "$config_path"
        sed -i 's|"name": "Change core to mednafen_ngp"|"name": "✓ Core is mednafen_ngp"|g' "$config_path"
    fi
}

update_core_config_name

if command -v sed &> /dev/null; then
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/mednafen_ngp_libretro.so "$1"|g' "$script_path"
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/mednafen_ngp_libretro.so "$1"|g' "$script_path"
fi