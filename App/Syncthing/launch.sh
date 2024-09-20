#!/bin/sh

silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1 #run silently via cli arg?

appdir=/mnt/SDCARD/App/Syncthing
sysdir=/mnt/SDCARD/.tmp_update
miyoodir=/mnt/SDCARD/miyoo

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

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

# Log file path
log_file="$appdir/spruceBackup.log"

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

syncthingpid() {
    pgrep "syncthing" > /dev/null
}

injectruntime() {
    log_message "Injecting config into runtime.sh..."
    sed -i '/# Syncthing Insertion Here (Do not remove)/a\sh /mnt/SDCARD/App/Syncthing/script/checkrun.sh #SYNCTHING INJECTOR #SYNCTHING INJECTOR' $sysdir/runtime.sh
    touch $appdir/config/gotime
    if grep -q "#SYNCTHING INJECTOR" "$sysdir/runtime.sh"; then
        log_message "Injection successful..."
    else
        log_message "Injection failed..."
    fi
}

repair_config() {
    local config="$appdir/config/config.xml"

    if grep -q "<listenAddress>dynamic+https://relays.syncthing.net/endpoint</listenAddress>" "$config"; then
        log_message "Config not generated correctly, manually repairing..."

        sed -i '/<listenAddress>dynamic+https:\/\/relays.syncthing.net\/endpoint<\/listenAddress>/d' "$config"
        sed -i '/<listenAddress>quic:\/\/0.0.0.0:41383<\/listenAddress>/d' "$config"

        sed -i 's|<listenAddress>tcp://0.0.0.0:41383</listenAddress>|<listenAddress>default</listenAddress>|' "$config"
        sed -i 's|<address>127.0.0.1:40379</address>|<address>0.0.0.0:8384</address>|' "$config"

        if grep -q "<address>0.0.0.0:8384</address>" "$config" && grep -q "<listenAddress>default</listenAddress>" "$config"; then
            log_message "Repair complete. GUI IP forced to 0.0.0.0"
        else
            log_message "Failed to repair config. Remove the app dir and try again"
        fi
    fi
}

startsyncthing() {
    if syncthingpid; then
		if [ "$silent_mode" -eq 0 ]; then
			show_image "$KILL_IMAGE_PATH"
		fi
        log_message "Already running. Stopping Syncthing..."
        killall -9 syncthing
        update_config "OFF"  # Update config.json to OFF
        log_message "Syncthing stopped."
    else
        log_message "Starting Syncthing..."
        $appdir/bin/syncthing serve --home=$appdir/config/ > $appdir/serve.log 2>&1 &
        update_config "ON"  # Update config.json to ON
        log_message "Syncthing started."
    fi
}

firststart() {
    if [ ! -f $appdir/config/config.xml ]; then
        log_message "Config file not found, generating..."
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
        log_message "IP already setup in config"
        sleep 1
        log_message "GUI IP is $IP:8384"
        skiplast=1
        sleep 5
    fi

    log_message "Setting IP, changing GUI IP:Port to $IP:8384"
    sed -i "s|<address>127.0.0.1:8384</address>|<address>0.0.0.0:8384</address>|g" $appdir/config/config.xml

    if [[ $? -eq 0 && $(grep -c "<address>0.0.0.0:8384</address>" $appdir/config/config.xml) -gt 0 ]]; then
        log_message "GUI IP set to $IP:8384"
        sleep 5
    else
        log_message "Failed to set IP address"
    fi
}

########################## GO TIME

log_message "Syncthing setup"

# Determine theme path
if [ -f "$THEME_JSON_FILE" ]; then
    THEME_PATH=$(awk -F'"' '/"theme":/ {print $4}' "$THEME_JSON_FILE")
    THEME_PATH="${THEME_PATH%/}/"

    if [ "${THEME_PATH: -1}" != "/" ]; then
        THEME_PATH="${THEME_PATH}/"
    fi

    APP_THEME_ICON_PATH="${THEME_PATH}Icons/App/"
fi

if [ "$silent_mode" -eq 0 ]; then
	if syncthingpid; then
		show_image "$KILL_IMAGE_PATH"
	else
		show_image "$IMAGE_PATH"
	fi
fi

log_message "Checking if we're already configured..."

if check_injector; then
    log_message "We're already configured."

    if syncthingpid; then
        log_message "Running. Killing until next reboot."
        killall -9 syncthing
        update_config "OFF"  # Update config.json to OFF
        log_message "Finished."
    else
        startsyncthing
    fi
else
    log_message "We're not configured, starting."
    firststart
    injectruntime
    changeguiip
    startsyncthing
    if [ "$skiplast" -ne 1 ]; then
        log_message "Browse to $IP:8384 to setup!"
    fi
fi

killall -9 show
