#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo X"
	touch /tmp/trimui_inputd/turbo_x
    ;;
0 )
    echo "Exit turbo X"
	rm /tmp/trimui_inputd/turbo_x
	;;
*)
    ;;
esac
