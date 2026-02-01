#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo R2"
	touch /tmp/trimui_inputd/turbo_r2
    ;;
0 )
    echo "Exit turbo R2"
	rm /tmp/trimui_inputd/turbo_r2
	;;
*)
    ;;
esac
