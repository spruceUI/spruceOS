#!/bin/sh

# Path to the runtime.sh and config.json files
RUNTIME_SH="/mnt/SDCARD/.tmp_update/runtime.sh"
CONFIG_JSON="/mnt/SDCARD/app/syncthing/config.json"

# Function to update config.json
update_config() {
    local status=$1
    local label
    local icon="/mnt/SDCARD/Icons/Default/App/syncthing.png"
    local launch="launch.sh"
    local description="Synchronize your files"

    if [ "$status" = "ON" ]; then
        label="SYNCTHING - ON"
    else
        label="SYNCTHING - OFF"
    fi

    cat > "$CONFIG_JSON" <<EOL
{
"label":	"$label",
"icon":"$icon",
"launch":	"$launch",
"description":	"$description"
}
EOL
}

# Check if the line exists in runtime.sh
if grep -q "sh /mnt/SDCARD/App/Syncthing/script/checkrun.sh" "$RUNTIME_SH"; then
    update_config "ON"
else
    update_config "OFF"
fi
