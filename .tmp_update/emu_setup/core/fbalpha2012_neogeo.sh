#!/bin/sh

EMU_DIR="$(dirname "$0")"
CONFIG="$EMU_DIR/config.json"
SYS_OPT="$EMU_DIR/system.opt"

update_core_config_name() {
    if [ -f "$CONFIG" ]; then
        sed -i 's|"name": "✓ Core is fbalpha2012_neogeo"|"name": "Change core to fbalpha2012_neogeo"|g' "$CONFIG"
        sed -i 's|"name": "✓ Core is fbneo"|"name": "Change core to fbneo"|g' "$CONFIG"
        sed -i 's|"name": "Change core to fbalpha2012_neogeo"|"name": "✓ Core is fbalpha2012_neogeo"|g' "$CONFIG"
    fi
}

update_core_config_name

sed -i 's/CORE=.*/CORE=\"fbalpha2012_neogeo\"/g' "$SYS_OPT"