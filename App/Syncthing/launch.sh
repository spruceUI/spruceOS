#!/bin/sh

appdir=/mnt/SDCARD/App/Syncthing
sysdir=/mnt/SDCARD/.tmp_update
miyoodir=/mnt/SDCARD/miyoo

# Path to the runtime.sh and config.json files
RUNTIME_SH="/mnt/SDCARD/.tmp_update/runtime.sh"
CONFIG_JSON="/mnt/SDCARD/app/syncthing/config.json"

# Default image path
IMAGE_PATH="/mnt/SDCARD/App/syncthing/syncthing.png"
KILL_IMAGE_PATH="$appdir/kill.png"

# Theme paths
THEME_JSON_FILE="/config/system.json"
DEFAULT_ICON_PATH="/mnt/SDCARD/icons/default/"
DEFAULT_ICON_SEL_PATH="${DEFAULT_ICON_PATH}sel/"
APP_DEFAULT_ICON_PATH="/mnt/SDCARD/Icons/Default/App/"
APP_THEME_ICON_PATH=""

# Function to show image
show_image() {
    local image=$1
    if [ ! -f "$image" ]; then
        echo "Image file not found at $image"
        exit 1
    fi
    killall -9 show
    show "$image" &
}

# Function to update config.json
update_config() {
    local status=$1
    local label
    local icon
    local launch="launch.sh"
    local description="Synchronize your files"

    # Determine icon path based on theme
    if [ -z "$APP_THEME_ICON_PATH" ]; then
        icon="/mnt/SDCARD/Icons/Default/App/syncthing.png"
    else
        icon="${APP_THEME_ICON_PATH}syncthing.png"
    fi

    if [ "$status" = "ON" ]; then
        label="Syncthing - ON"
    else
        label="Syncthing - OFF"
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

LD_LIBRARY_PATH="$appdir/lib:/lib:/config/lib:$miyoodir/lib:$sysdir/lib:$sysdir/lib/parasyte"
PATH="$sysdir/bin:$PATH"

skiplast=0

check_injector() {
    if grep -q "#SYNCTHING INJECTOR" "$sysdir/runtime.sh"; then
        return 0
    else
        return 1
    fi
}

build_infoPanel() {
    local message="$1"
    local title="Syncthing Installer"

    infoPanel --title "$title" --message "$message" --persistent &
    touch /tmp/dismiss_info_panel
    sync
    sleep 1
}

syncthingpid() {
    pgrep "syncthing" > /dev/null
}

injectruntime() {
    build_infoPanel "Injecting config into runtime.sh..."
    sed -i '/# Auto launch/i \	sh /mnt/SDCARD/App/Syncthing/script/checkrun.sh #SYNCTHING INJECTOR #SYNCTHING INJECTOR' $sysdir/runtime.sh
    touch $appdir/config/gotime
    if grep -q "#SYNCTHING INJECTOR" "$sysdir/runtime.sh"; then
        build_infoPanel "Injection successful..."
    else
        build_infoPanel "Injection failed..."
    fi
}

repair_config() {
    local config="$appdir/config/config.xml"

    if grep -q "<listenAddress>dynamic+https://relays.syncthing.net/endpoint</listenAddress>" "$config"; then
        build_infoPanel "Config not generated correctly, \n Manually repairing"

        sed -i '/<listenAddress>dynamic+https:\/\/relays.syncthing.net\/endpoint<\/listenAddress>/d' "$config"
        sed -i '/<listenAddress>quic:\/\/0.0.0.0:41383<\/listenAddress>/d' "$config"

        sed -i 's|<listenAddress>tcp://0.0.0.0:41383</listenAddress>|<listenAddress>default</listenAddress>|' "$config"
        sed -i 's|<address>127.0.0.1:40379</address>|<address>0.0.0.0:8384</address>|' "$config"

        if grep -q "<address>0.0.0.0:8384</address>" "$config" && grep -q "<listenAddress>default</listenAddress>" "$config"; then
            build_infoPanel "Repair complete. \n GUI IP Forced to 0.0.0.0"
        else
            build_infoPanel "Failed to repair config \n Remove the app dir \n and try again"
        fi
    fi
}

startsyncthing() {
    if syncthingpid; then
        show_image "$KILL_IMAGE_PATH"
        build_infoPanel "Already running. Stopping Syncthing..."
        killall -9 syncthing
        update_config "OFF"  # Update config.json to OFF
        build_infoPanel "Syncthing stopped."
    else
        build_infoPanel "Starting Syncthing..."
        $appdir/bin/syncthing serve --home=$appdir/config/ > $appdir/serve.log 2>&1 &
        update_config "ON"  # Update config.json to ON
        build_infoPanel "Syncthing started."
    fi
}

firststart() {
    if [ ! -f $appdir/config/config.xml ]; then
        build_infoPanel "Config file not found, generating..."
        # Ensure loopback interface is enabled and running as expected
        # So we'll restart it
        ifconfig lo down
        sleep 5
        ifconfig lo up
        sleep 5
        $appdir/bin/syncthing generate --no-default-folder --home=$appdir/config/ > $appdir/generate.log 2>&1 &
        sleep 5

        repair_config # check if the config was generated correctly

        pkill syncthing
    fi
}

changeguiip() {
    sync
    IP=$(ip route get 1 | awk '{print $NF;exit}')

    if grep -q "<address>0.0.0.0:8384</address>" $appdir/config/config.xml; then
        build_infoPanel "IP already setup in config"
        sleep 1
        build_infoPanel "GUI IP is $IP:8384"
        skiplast=1
        sleep 5
    fi

    build_infoPanel "Setting IP" "Changing GUI IP:Port to $IP:8384"
    sed -i "s|<address>127.0.0.1:8384</address>|<address>0.0.0.0:8384</address>|g" $appdir/config/config.xml

    if [[ $? -eq 0 && $(grep -c "<address>0.0.0.0:8384</address>" $appdir/config/config.xml) -gt 0 ]]; then
        build_infoPanel "GUI IP set to $IP:8384"
        sleep 5
    else
        build_infoPanel "Failed to set IP address"
    fi
}

########################## GO TIME

build_infoPanel "Syncthing setup"

# Determine theme path
if [ -f "$THEME_JSON_FILE" ]; then
    THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
    THEME_PATH="${THEME_PATH%/}/"

    if [ "${THEME_PATH: -1}" != "/" ]; then
        THEME_PATH="${THEME_PATH}/"
    fi

    APP_THEME_ICON_PATH="${THEME_PATH}Icons/App/"
fi

if syncthingpid; then
    show_image "$KILL_IMAGE_PATH"
else
    show_image "$IMAGE_PATH"
fi

build_infoPanel "Checking if we're already configured..."

if check_injector; then
    build_infoPanel "We're already configured.."

    if syncthingpid; then
        build_infoPanel "Running. killing until next reboot"
        killall -9 syncthing
        update_config "OFF"  # Update config.json to OFF
        build_infoPanel "Finished" "Done..."
    else
        startsyncthing
    fi
else
    build_infoPanel "We're not configured, starting"
    firststart
    injectruntime
    changeguiip
    startsyncthing
    if [ "$skiplast" -ne 1 ]; then
        build_infoPanel "Browse to $IP:8384 to setup!"
    fi
fi

killall -9 show



