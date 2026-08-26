#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo B"
	touch /tmp/trimui_inputd/turbo_b
    ;;
0 )
    echo "Exit turbo B"
	rm /tmp/trimui_inputd/turbo_b
	;;
*)
    ;;
esac
