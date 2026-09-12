#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo L2"
	touch /tmp/trimui_inputd/turbo_l2
    ;;
0 )
    echo "Exit turbo L2"
	rm /tmp/trimui_inputd/turbo_l2
	;;
*)
    ;;
esac
