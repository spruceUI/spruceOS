#!/bin/sh
# Switch scene action: Quiet Mode through spruce's own volume system.
#
# trimui_scened runs this with arg 1 (switch on -> quiet) / 0 (switch off).
# The stock com.trimui.quiet.sh poked "tinymix set 9 N", but on this device
# control 9 is "DACL DACR Swap" (an Off/On enum), not a volume control, so the
# stock script never attenuated anything and could swap the L/R channels. Route
# through set_volume instead, which updates SYSTEM_JSON .vol so the in-UI volume
# reading matches and the real DAC volume actually changes.
#
# Unlike the Brick (whose switch draws its own on-screen toast), the Smart Pro S
# switch has no popup, so we let set_volume show the stock volume OSD in game --
# it is the only feedback the user gets that the switch did something.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

QUIET_VOL=4   # spruce volume scale is 0-20; ~20% is low but audible
SAVED_VOL_FILE=/tmp/system/quiet_saved_vol

mkdir -p /tmp/system/

case "$1" in
    1)
        # Remember the current volume so we can restore it on exit.
        cur="$(get_volume_level)"
        [ -z "$cur" ] && cur=0
        echo "$cur" > "$SAVED_VOL_FILE"
        set_volume "$QUIET_VOL"
        ;;
    0)
        saved="$(cat "$SAVED_VOL_FILE" 2>/dev/null)"
        [ -z "$saved" ] && saved=0
        set_volume "$saved"
        rm -f "$SAVED_VOL_FILE"
        ;;
esac
