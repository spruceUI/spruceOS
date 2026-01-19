#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo Y"
	touch /tmp/trimui_inputd/turbo_y
    ;;
0 )
    echo "Exit turbo Y"
	rm /tmp/trimui_inputd/turbo_y
	;;
*)
    ;;
esac
