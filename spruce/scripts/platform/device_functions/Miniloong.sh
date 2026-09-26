#!/bin/sh
# Miniloong Pocket 1 device functions. Everything the base OS decides is in
# dArkMossCommon.sh; this file holds what is particular to this unit.

. "/mnt/SDCARD/spruce/scripts/platform/device_functions/dArkMossCommon.sh"

# The jack is the extcon named rk-headset; its index follows probe order.
are_headphones_plugged_in() {
    for _x in /sys/class/extcon/*; do
        [ "$(cat "$_x/name" 2>/dev/null)" = "rk-headset" ] || continue
        grep -q 'HEADPHONE=1' "$_x/state" 2>/dev/null
        return
    done
    return 1
}

set_event_arg_for_idlemon() {
    EVENT_ARG="-e $EVENT_PATH_READ_INPUTS_SPRUCE"
}
