#!/bin/sh

BIN_PATH="/mnt/SDCARD/spruce/bin"

/mnt/SDCARD/App/ShowOutputTest/read_button_test.sh | $BIN_PATH/showOutput -x 5 -f 30 -w -d -t "<< SHOW OUTPUT TEST >>"

return 0
