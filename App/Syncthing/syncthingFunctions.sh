#! /bin/sh

. /mnt/SDCARD/.tmp_update/scripts/helperFunctions.sh

SYNCTHING_DIR=/mnt/SDCARD/App/Syncthing
SYNCTHING_CONFIG_FILE="$SYNCTHING_DIR/config.json"

syncthing_check(){
    if [ -f /mnt/SDCARD/.tmp_update/flags/syncthing.lock ]; then
        start_syncthing_process
    else
        sed -i 's|ON|OFF|' $SYNCTHING_CONFIG_FILE
    fi
}

start_syncthing_process(){
    log_message "Starting Syncthing..."
    $SYNCTHING_DIR/bin/syncthing serve --home=$SYNCTHING_DIR/config/ > $SYNCTHING_DIR/serve.log 2>&1 &
    sed -i 's|OFF|ON|' $SYNCTHING_CONFIG_FILE
}