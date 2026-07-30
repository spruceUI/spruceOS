#!/bin/sh
# Switch scene action: Silent Mode through spruce's own volume system.
#
# trimui_scened runs this with arg 1 (switch on -> silent) / 0 (switch off).
# The stock com.trimui.silent.sh hard-muted the speaker via /sys but never told
# spruce, so its stored .vol (and the settings slider) stayed at the old level
# while muted. Drop .vol to 0 through set_volume so the UI reflects the mute,
# and keep the speaker hard-mute as a backstop. Restore the prior volume on exit.
#
# As on scene-quiet.sh, we let set_volume show the stock volume OSD: the Smart
# Pro S switch has no toast of its own, so the OSD is the user's only feedback.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

SAVED_VOL_FILE=/tmp/system/silent_saved_vol

mkdir -p /tmp/system/

case "$1" in
    1)
        # Remember the current volume so we can restore it on exit.
        cur="$(get_volume_level)"
        [ -z "$cur" ] && cur=0
        echo "$cur" > "$SAVED_VOL_FILE"
        set_volume 0
        # Belt and suspenders: cut the speaker amp outright.
        echo 1 > /sys/class/speaker/mute
        touch /tmp/system/muted
        ;;
    0)
        echo 0 > /sys/class/speaker/mute
        rm -f /tmp/system/muted
        saved="$(cat "$SAVED_VOL_FILE" 2>/dev/null)"
        [ -z "$saved" ] && saved=0
        set_volume "$saved"
        rm -f "$SAVED_VOL_FILE"
        ;;
esac
