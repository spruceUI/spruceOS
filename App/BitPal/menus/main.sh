#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh


case "$1" in
    status | stats) display_bitpal_stats ;;
esac



# return to main BitPal menu
/mnt/SDCARD/spruce/flip/bin/python3 \
/mnt/SDCARD/App/PyUI/main-ui/OptionSelectUI.py \
"BitPal" /mnt/SDCARD/App/BitPal/menus/main.json
