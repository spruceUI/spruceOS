#!/bin/sh

BIN_PATH="/mnt/SDCARD/spruce/bin"

/mnt/SDCARD/App/ShowOutputTest/read_button_test.sh | $BIN_PATH/showOutput -k __EXIT__ -f 30 -w -t "<< SHOW OUTPUT TEST >>"

return 0
