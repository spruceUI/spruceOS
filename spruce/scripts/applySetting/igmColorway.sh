#!/bin/sh
# changeCmd for the in-game menu colourway: materialise the chosen file so the
# RetroArch binary only ever has to open one path. Backgrounded - PyUI runs
# changeCmd on the UI thread.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

(
    name="$(get_config_value '.menuOptions."Emulator Settings".raIgmColorway.selected' "spruce")"
    src="/mnt/SDCARD/RetroArch/igm/${name}.json"
    [ -f "$src" ] || src="/mnt/SDCARD/RetroArch/igm/spruce.json"
    [ -f "$src" ] && cp -f "$src" "/mnt/SDCARD/RetroArch/igm.json"
) </dev/null >/dev/null 2>&1 &
