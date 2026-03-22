#!/bin/sh

. "/mnt/SDCARD/spruce/scripts/helperFunctions.sh"

sleep 10
log_message "Enforcing SMART mode"
set_smart "$1"

