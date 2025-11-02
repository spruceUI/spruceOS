#!/bin/sh
echo "============= Joystick ============"

case "$1" in
1 ) 
    echo "Joystick On"
	touch /tmp/trimui_inputd/input_no_dpad
	touch /tmp/trimui_inputd/input_dpad_to_joystick
    ;;
0 )
    echo "Joystick Off"
    rm /tmp/trimui_inputd/input_no_dpad
    rm /tmp/trimui_inputd/input_dpad_to_joystick
	;;
*)
    ;;
esac
