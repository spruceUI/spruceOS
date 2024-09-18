#!/bin/sh

# Path to the runtime.sh and config.json files
RUNTIME_SH="/mnt/SDCARD/.tmp_update/runtime.sh"
if [ -f "/mnt/SDCARD/app/syncthing/config.json" ]; then
    CONFIG_JSON="/mnt/SDCARD/app/syncthing/config.json"
elif [ -f "/mnt/SDCARD/app/syncthing/config_hidden.json" ]; then
    CONFIG_JSON="/mnt/SDCARD/app/syncthing/config_hidden.json"
fi
# Function to update config.json
update_config() {
    local status=$1
    local label
    local icon
    local launch="launch.sh"
    local description="Synchronize your files"

    # Extract the icon path using grep and sed
    icon=$(grep '"icon"' "$CONFIG_JSON" | sed -E 's/.*"icon"\s*:\s*"([^"]*)".*/\1/')

    # Debugging: Print the extracted icon value
    echo "Extracted icon: $icon"

    if [ "$status" = "ON" ]; then
        label="SYNCTHING - ON"
    else
        label="SYNCTHING - OFF"
    fi

    cat > "$CONFIG_JSON" <<EOL
{
"label": "$label",
"icon": "$icon",
"launch": "$launch",
"description": "$description"
}
EOL
}

# Check if the line exists in runtime.sh
if grep -q "sh /mnt/SDCARD/App/Syncthing/script/checkrun.sh" "$RUNTIME_SH"; then
    update_config "ON"
else
    update_config "OFF"
fi
