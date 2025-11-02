#!/bin/sh
echo "============= scene turbo ============"

case "$1" in
1 ) 
    echo "Enter turbo R"
	touch /tmp/trimui_inputd/turbo_r
    ;;
0 )
    echo "Exit turbo R"
	rm /tmp/trimui_inputd/turbo_r
	;;
*)
    ;;
esac
