#!/bin/sh

BIN_PATH="/mnt/SDCARD/.tmp_update/bin"
FLAG_PATH="/mnt/SDCARD/spruce/flags"

cd $BIN_PATH
./easyConfig $FLAG_PATH/gs_config -t "<< Game Switcher Settings >>" -o $FLAG_PATH/gs_options

