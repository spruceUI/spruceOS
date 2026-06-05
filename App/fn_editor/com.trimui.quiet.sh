#!/bin/sh
# Quiet Mode: drop the volume to a low level through spruce's own set_volume so
# the in-UI volume reading matches, then restore the previous volume on exit.
#
# The stock script poked an ALSA mixer control directly (tinymix set 9 N), which
# spruce neither reads nor respects, so nothing audible changed and the settings
# slider stayed wrong. Going through set_volume updates SYSTEM_JSON .vol too.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

QUIET_VOL=4   # spruce volume scale is 0-20; ~20% is low but audible
SAVED_VOL_FILE=/tmp/system/quiet_saved_vol

echo "============= scene quiet ============"
mkdir -p /tmp/system/

case "$1" in
1 )
    echo "Enter quiet"
    # Remember the current volume so we can restore it on exit
    cur="$(get_volume_level)"
    [ -z "$cur" ] && cur=0
    echo "$cur" > "$SAVED_VOL_FILE"
    # Lower spruce's volume (updates SYSTEM_JSON .vol -> UI reflects it)
    set_volume "$QUIET_VOL"
    ;;
0 )
    echo "Exit quiet"
    # Restore the volume we had before entering quiet
    saved="$(cat "$SAVED_VOL_FILE" 2>/dev/null)"
    [ -z "$saved" ] && saved=0
    set_volume "$saved"
    rm -f "$SAVED_VOL_FILE"
    ;;
*)
    ;;
esac
