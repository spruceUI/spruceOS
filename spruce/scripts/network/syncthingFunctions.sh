#! /bin/sh

export STGUIADDRESS="http://0.0.0.0:8384"
export STNOUPGRADE="true"

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SYNCTHING_DIR=/mnt/SDCARD/spruce/bin/Syncthing

if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
    ST_BIN=$SYNCTHING_DIR/bin/syncthing
else # aarch64
    ST_BIN=/mnt/SDCARD/spruce/bin64/Syncthing/bin/syncthing
fi

# Generic Startup
# Should only be used in contexts where firststart has already been called
start_syncthing_process(){
    if pgrep "syncthing" >/dev/null; then
        log_message "Syncthing: Already running, skipping start"
        return
    fi

    if grep -q "<address>127.0.0.1:8384</address>" $SYNCTHING_DIR/config/config.xml; then
      repair_config
      changeguiip
    fi
    
    log_message "Syncthing: Starting Syncthing..."
    $ST_BIN serve --no-upgrade --gui-address="$STGUIADDRESS" --home=$SYNCTHING_DIR/config/ > $SYNCTHING_DIR/serve.log 2>&1 &
}

stop_syncthing_process(){
    killall -9 syncthing
}

# First start script
# Well generate the config files, set the gui ip and start the process
# Adds the syncthing flag implying setup was ran
syncthing_startup_process() {
    firststart
    changeguiip
    start_syncthing_process
}

firststart() {
    if [ ! -f $SYNCTHING_DIR/config/config.xml ]; then
        log_message "Syncthing: Config file not found, generating..."
        # Ensure loopback interface is enabled and running as expected
        # So we'll restart it
        ifconfig lo down
        sleep 5
        ifconfig lo up
        sleep 5
        $ST_BIN generate --gui-user=spruce --gui-password=happygaming --no-default-folder --home=$SYNCTHING_DIR/config/ > $SYNCTHING_DIR/generate.log 2>&1 &
        sleep 5

        repair_config # check if the config was generated correctly

        pkill syncthing
    fi
}

repair_config() {
    local config="$SYNCTHING_DIR/config/config.xml"

    if grep -q "<listenAddress>dynamic+https://relays.syncthing.net/endpoint</listenAddress>" "$config"; then
        log_message "Syncthing: Config not generated correctly, manually repairing..."

        sed -i '/<listenAddress>dynamic+https:\/\/relays.syncthing.net\/endpoint<\/listenAddress>/d' "$config"
        sed -i '/<listenAddress>quic:\/\/0.0.0.0:41383<\/listenAddress>/d' "$config"

        sed -i 's|<listenAddress>tcp://0.0.0.0:41383</listenAddress>|<listenAddress>default</listenAddress>|' "$config"
        # This line is redundant as it's already handled in changeguiip function
        # sed -i 's|<address>127.0.0.1:40379</address>|<address>0.0.0.0:8384</address>|' "$config"

        if grep -q "<address>0.0.0.0:8384</address>" "$config" && grep -q "<listenAddress>default</listenAddress>" "$config"; then
            log_message "Syncthing: Repair complete. GUI IP forced to 0.0.0.0"
        else
            log_message "Syncthing: Failed to repair config. Remove the app dir and try again"
        fi
    fi
}

changeguiip() {
    sync
    IP=$(ip route get 1 | awk '{print $NF;exit}')

    if grep -q "<address>0.0.0.0:8384</address>" $SYNCTHING_DIR/config/config.xml; then
        log_message "Syncthing: IP already setup in config"
        sleep 1
        log_message "Syncthing: GUI IP is $IP:8384"
        skiplast=1
        sleep 5
    fi

    log_message "Syncthing: Setting IP, changing GUI IP:Port to $IP:8384"
    sed -i "s|<address>127.0.0.1:8384</address>|<address>0.0.0.0:8384</address>|g" $SYNCTHING_DIR/config/config.xml

    if [[ $? -eq 0 && $(grep -c "<address>0.0.0.0:8384</address>" $SYNCTHING_DIR/config/config.xml) -gt 0 ]]; then
        log_message "Syncthing: GUI IP set to $IP:8384"
        sleep 5
    else
        log_message "Syncthing: Failed to set IP address"
    fi
}
