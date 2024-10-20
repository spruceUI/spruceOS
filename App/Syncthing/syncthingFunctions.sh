#! /bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SYNCTHING_DIR=/mnt/SDCARD/App/Syncthing
SYNCTHING_CONFIG_FILE="$SYNCTHING_DIR/config.json"

syncthing_check(){
    if flag_check "syncthing"; then
        start_syncthing_process
    else
        sed -i 's|- On|- Off|' $SYNCTHING_CONFIG_FILE
    fi
}

start_syncthing_process(){
    log_message "Starting Syncthing..."
    $SYNCTHING_DIR/bin/syncthing serve --home=$SYNCTHING_DIR/config/ > $SYNCTHING_DIR/serve.log 2>&1 &
    sed -i 's|- Off|- On|' $SYNCTHING_CONFIG_FILE
    sed -i 's|"#label"|"label"|' $SYNCTHING_CONFIG_FILE
}