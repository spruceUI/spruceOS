#! /bin/sh
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

export STGUIADDRESS="http://0.0.0.0:8384"
export STNOUPGRADE="true"

export ST_DIR=/mnt/SDCARD/Saves/syncthing
ST_USER=spruce
ST_PASS=happygaming

if [ "$PLATFORM_ARCHITECTURE" = "armhf" ]; then
    ST_BIN=/mnt/SDCARD/spruce/bin/Syncthing/bin/syncthing
else # aarch64
    ST_BIN=/mnt/SDCARD/spruce/bin64/Syncthing/bin/syncthing
fi

generate_config() {
    log_message "Syncthing: Config file not found, generating..."

    $ST_BIN generate --gui-user="$ST_USER" --gui-password="$ST_PASS" --home="$ST_DIR"/config/ > "$ST_DIR"/generate.log
    repair_config
}

repair_config() (
    config="$ST_DIR/config/config.xml"

    if grep -q "<listenAddress>dynamic+https://relays.syncthing.net/endpoint</listenAddress>" "$config"; then
        log_message "Syncthing: Config not generated correctly, manually repairing..."

        sed -i '/<listenAddress>dynamic+https:\/\/relays.syncthing.net\/endpoint<\/listenAddress>/d' "$config"
        sed -i '/<listenAddress>quic:\/\/0.0.0.0:41383<\/listenAddress>/d' "$config"

        sed -i 's|<listenAddress>tcp://0.0.0.0:41383</listenAddress>|<listenAddress>default</listenAddress>|' "$config"
        sed -i "s|<address>127.0.0.1:8384</address>|<address>0.0.0.0:8384</address>|g" "$config"

        if grep -q "<address>0.0.0.0:8384</address>" "$config" && grep -q "<listenAddress>default</listenAddress>" "$config"; then
            log_message "Syncthing: Repair complete. GUI IP forced to 0.0.0.0"
        else
            log_message "Syncthing: Failed to repair config. Remove the config directory and try again."
        fi
    fi
)

run_syncthing() {
    "$ST_BIN" serve --no-upgrade --gui-address="$STGUIADDRESS" --home="$ST_DIR"/config/ > "$ST_DIR"/serve.log 2>&1
}

start_syncthing_process() {
    if [ ! -f "$ST_DIR"/config/config.xml ]; then
        (generate_config && run_syncthing) &
    else
        run_syncthing &
    fi
}

stop_syncthing_process(){
    killall -9 syncthing
}
