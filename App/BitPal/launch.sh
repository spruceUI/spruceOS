#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh
. /mnt/SDCARD/App/BitPal/BitPalFunctions.sh

[ ! -f $BITPAL_JSON ] && initialize_bitpal_data
[ ! -f "$MISSION_JSON" ] && initialize_mission_data


set_random_good_mood
FACE="$(get_face)"
display -d 2 -t "$FACE" -s 80 -p 50

GREETING="$(get_random_greeting)"
display --okay -t "$GREETING" -s 36 -p 50
sleep 0.1

FACT="$(get_random_fact)"

display --okay -t "$FACT" -s 36 -p 50
sleep 0.1

# Launch main BitPal menu
export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/miyoo/lib"
/mnt/SDCARD/spruce/flip/bin/python3 \
/mnt/SDCARD/App/PyUI/main-ui/OptionSelectUI.py \
"BitPal" "/mnt/SDCARD/App/BitPal/menus/main.json"


set_random_negative_mood
GUILT_TRIP="$(get_random_guilt_trip)"
display --okay -t "$GUILT_TRIP" -s 36 -p 50
sleep 0.1