#!/bin/sh

# Source the helper functions
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

for i in $(seq 1 3); do 
    echo 1 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    sleep 0.3
    echo 0 > /sys/devices/platform/sunxi-led/leds/led1/brightness
    sleep 0.3
done

if flag_check "ledon"; then
    sed -i 's/LED - On/LED - Off/' /mnt/SDCARD/App/LEDOn/config.json
    flag_remove "ledon"
elif flag_check "tlon"; then
    sed -i 's/LED - On In Menu Only/LED - On/' /mnt/SDCARD/App/LEDOn/config.json
    flag_remove "tlon"
    flag_add "ledon"
else
    sed -i 's/LED - Off/LED - On In Menu Only/' /mnt/SDCARD/App/LEDOn/config.json
    flag_add "tlon"
    flag_remove "ledon"
fi
