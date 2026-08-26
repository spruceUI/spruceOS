#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo L"
	touch /tmp/trimui_inputd/turbo_l
    ;;
0 )
    echo "Exit turbo L"
	rm /tmp/trimui_inputd/turbo_l
	;;
*)
    ;;
esac
