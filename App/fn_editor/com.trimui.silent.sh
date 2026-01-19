#!/bin/sh
echo "============= scene silent ============"
mkdir -p /tmp/system/
case "$1" in
1 ) 
    echo "Enter silent"
	echo 1 > /sys/class/speaker/mute 
    touch /tmp/system/muted
    ;;
0 )
    echo "Exit silent"
	echo 0 > /sys/class/speaker/mute
    rm -f /tmp/system/muted
	;;
*)
    ;;
esac
