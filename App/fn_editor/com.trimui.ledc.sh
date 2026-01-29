#!/bin/sh
echo "============= scene LEDC ============"

case "$1" in
1 ) 
        echo "disable LED"
        echo "set ledswitch 0"
        echo -n 0 > /tmp/system/enable_led
        ;;
0 )
        echo "resume LED"
        echo "set ledswitch 1"
        echo -n 1 > /tmp/system/enable_led
	;;
*)
        ;;
esac

