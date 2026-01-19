#!/bin/sh
LED_ON=`/usr/trimui/bin/systemval ledswitch`

echo "get ledswitch:"$LED_ON

case "$LED_ON" in
1 ) 
    echo "set LED on"
    LED_ON=0
    ;;

* )
    echo "set LED off"
    LED_ON=1
    ;;
esac

echo "set ledswitch:"$LED_ON
echo -n $LED_ON > /tmp/system/enable_led
