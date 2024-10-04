#!/bin/sh

silent_mode=0
[ "$1" = "--silent" ] && silent_mode=1 #run silently via cli arg?

appdir=/mnt/SDCARD/App/Syncthing
sysdir=/mnt/SDCARD/.tmp_update
miyoodir=/mnt/SDCARD/miyoo

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/Syncthing/syncthingFunctions.sh

# Default image path
IMAGE_PATH="$appdir/imgs/syncthing.png"
KILL_IMAGE_PATH="$appdir/imgs/kill.png"

# Log file path
log_file="$appdir/spruceBackup.log"


LD_LIBRARY_PATH="$appdir/lib:/lib:/config/lib:$miyoodir/lib:$sysdir/lib:$sysdir/lib/parasyte"
PATH="$sysdir/bin:$PATH"
CONFIG_JSON="$appdir/config.json"


skiplast=0

syncthingpid() {
    pgrep "syncthing" > /dev/null
}

repair_config() {
    local config="$appdir/config/config.xml"

    if grep -q "<listenAddress>dynamic+https://relays.syncthing.net/endpoint</listenAddress>" "$config"; then
        log_message "Config not generated correctly, manually repairing..."

        sed -i '/<listenAddress>dynamic+https:\/\/relays.syncthing.net\/endpoint<\/listenAddress>/d' "$config"
        sed -i '/<listenAddress>quic:\/\/0.0.0.0:41383<\/listenAddress>/d' "$config"

        sed -i 's|<listenAddress>tcp://0.0.0.0:41383</listenAddress>|<listenAddress>default</listenAddress>|' "$config"
        # This line is redundant as it's already handled in changeguiip function
        # sed -i 's|<address>127.0.0.1:40379</address>|<address>0.0.0.0:8384</address>|' "$config"

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
        sed -i 's|- On|- Off|' $CONFIG_JSON
        flag_remove "syncthing"
        log_message "Syncthing stopped."
    else
        start_syncthing_process
        log_message "Syncthing started."
        flag_add "syncthing"
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

if [ "$silent_mode" -eq 0 ]; then
    if flag_check "syncthing"; then
        show_image "$KILL_IMAGE_PATH"
    else
        show_image "$IMAGE_PATH"
    fi
fi

log_message "Checking if we're already configured..."

if flag_check "syncthing"; then
    log_message "Flag found, stopping syncthing."

    if syncthingpid; then
        log_message "Running. Killing until next reboot."
        killall -9 syncthing
        sed -i 's|- On|- Off|' $CONFIG_JSON
        flag_remove "syncthing"
        log_message "Finished."
    else
        startsyncthing
    fi
else
    log_message "Flag not found, starting syncthing."
    firststart
    changeguiip
    startsyncthing
    if [ "$skiplast" -ne 1 ]; then
        log_message "Browse to $IP:8384 to setup!"
    fi
fi

killall -9 show
