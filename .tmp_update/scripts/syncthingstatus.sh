#!/bin/sh

# Path to the runtime.sh and config.json files
RUNTIME_SH="/mnt/SDCARD/.tmp_update/runtime.sh"
CONFIG_JSON="/mnt/SDCARD/app/syncthing/config.json"

# Function to update config.json
update_config() {
    local status=$1
    local label
    local name
    local icon
    local launch="launch.sh"
    local description="Synchronize your files"

    # Extract the icon path using grep and sed
    icon=$(grep '"icon"' "$CONFIG_JSON" | sed -E 's/.*"icon"\s*:\s*"([^"]*)".*/\1/')

    # Debugging: Print the extracted icon value
    echo "Extracted icon: $icon"

    if [ "$status" = "ON" ]; then
        name="SYNCTHING - ON"
        label="label"
    else
        name="SYNCTHING - OFF"
        label="#label"
    fi

    cat > "$CONFIG_JSON" <<EOL
{
"$label": "$name",
"icon": "$icon",
"launch": "$launch",
"description": "$description",
"expert": true
}
EOL
}

# Check if the line exists in runtime.sh
if grep -q "sh /mnt/SDCARD/App/Syncthing/script/checkrun.sh" "$RUNTIME_SH"; then
    update_config "ON"
else
    update_config "OFF"
fi
