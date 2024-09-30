#!/bin/sh

EMU_NAME="$(echo "$1" | cut -d'/' -f5)"
CONFIG="/mnt/SDCARD/Emu/${EMU_NAME}/config.json"
SYS_OPT="/mnt/SDCARD/Emu/.emu_setup/options/${EMU_NAME}.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is fbalpha2012_cps1"|"name": "Change core to fbalpha2012_cps1"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is fbalpha2012_cps2"|"name": "Change core to fbalpha2012_cps2"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is fbalpha2012_cps3"|"name": "Change core to fbalpha2012_cps3"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is fbalpha2012_neogeo"|"name": "Change core to fbalpha2012_neogeo"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is fbneo"|"name": "Change core to fbneo"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is mame2003_plus"|"name": "Change core to mame2003_plus"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is fbalpha2012"|"name": "Change core to fbalpha2012"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is km_mame2003_xtreme"|"name": "Change core to km_mame2003_xtreme"|g' "$CONFIG"
        sed -i 's|"name": "Change core to fbneo"|"name": "✓ Core is fbneo"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"fbneo\"/g' "$SYS_OPT"
