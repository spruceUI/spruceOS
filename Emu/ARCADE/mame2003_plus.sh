#!/bin/sh

current_dir="$(dirname "$0")"
script_path="$current_dir/launch.sh"
config_path="$current_dir/config.json"

update_core_config_name() {
    if [ -f "$config_path" ]; then
        sed -i 's|"name": "✓ Core is fbneo"|"name": "Change core to fbneo"|g' "$config_path"
        sed -i 's|"name": "✓ Core is mame2003_plus"|"name": "Change core to mame2003_plus"|g' "$config_path"
        sed -i 's|"name": "✓ Core is fbalpha2012"|"name": "Change core to fbalpha2012"|g' "$config_path"
        sed -i 's|"name": "✓ Core is km_mame2003_xtreme"|"name": "Change core to km_mame2003_xtreme"|g' "$config_path"
        sed -i 's|"name": "Change core to mame2003_plus"|"name": "✓ Core is mame2003_plus"|g' "$config_path"
    fi
}

update_core_config_name

if command -v sed &> /dev/null; then
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/ra32.miyoo -v -L $RA_DIR/.retroarch/cores/mame2003_plus_libretro.so "$1"|g' "$script_path"
    sed -i 's|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/[^"]*\.so "$1"|HOME=$RA_DIR/ $RA_DIR/retroarch -v -L $RA_DIR/.retroarch/cores/mame2003_plus_libretro.so "$1"|g' "$script_path"
fi