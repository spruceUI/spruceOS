#!/bin/sh
echo "============= scene quiet ============"

case "$1" in
1 ) 
    echo "Enter quiet"
	tinymix set 9 4
    ;;
0 )
    echo "Exit quiet"
	tinymix set 9 1
	;;
*)
    ;;
esac
