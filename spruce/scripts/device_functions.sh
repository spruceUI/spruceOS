#!/bin/sh

# Intended to be sourced by helperFunctions.sh but NOT anywhere else
# It relies on functions inside helperFunctions.sh to operate properly
# (Not everything was cleanly broken apart since this is a refactor, in the future
#  we can try to make the file import chain cleaner)

# Ensure all methods are defined, and just logged if missing
. "/mnt/SDCARD/spruce/scripts/platform/device.sh"


# Source the correct file for the detected platform
platform_file="/mnt/SDCARD/spruce/scripts/platform/device_functions/$PLATFORM.sh"

if [ -f "$platform_file" ]; then
    . "$platform_file"
else
    log_message "No platform functions file found for platform: $PLATFORM : $platform_file"
fi