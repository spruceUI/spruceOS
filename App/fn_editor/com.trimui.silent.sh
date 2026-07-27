#!/bin/sh
# Silent Mode: hard-mute the speaker and reflect it in spruce's volume value so
# the in-UI volume reading matches. On exit, restore the volume that was set
# before entering silent.
#
# Without the set_volume calls the speaker mutes but spruce's stored vol (and the
# settings slider) stays at its old value, so the UI looks wrong while muted.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SAVED_VOL_FILE=/tmp/system/silent_saved_vol

echo "============= scene silent ============"
mkdir -p /tmp/system/

case "$1" in
1 )
    echo "Enter silent"
    # Remember the current volume so we can restore it on exit
    cur="$(get_volume_level)"
    [ -z "$cur" ] && cur=0
    echo "$cur" > "$SAVED_VOL_FILE"
    # Drop spruce's volume to 0 (updates SYSTEM_JSON .vol -> UI reflects it).
    # Pass "true false" so the config is saved but the stock volume OSD popup
    # is not shown; the switch already shows its own toast.
    set_volume 0 true false
    # Belt and suspenders: cut the speaker amp outright
    echo 1 > /sys/class/speaker/mute
    touch /tmp/system/muted
    ;;
0 )
    echo "Exit silent"
    echo 0 > /sys/class/speaker/mute
    rm -f /tmp/system/muted
    # Restore the volume we had before entering silent (no OSD popup)
    saved="$(cat "$SAVED_VOL_FILE" 2>/dev/null)"
    [ -z "$saved" ] && saved=0
    set_volume "$saved" true false
    rm -f "$SAVED_VOL_FILE"
    ;;
*)
    ;;
esac
