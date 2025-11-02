#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo A"
	touch /tmp/trimui_inputd/turbo_a
    ;;
0 )
    echo "Exit turbo A"
	rm /tmp/trimui_inputd/turbo_a
	;;
*)
    ;;
esac
