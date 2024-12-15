#!/bin/sh

SCRIPT_PATH="/mnt/SDCARD/spruce/scripts"

echo "Please press Button A/B to exit or X/Y to continue:"
BUTTON=$($SCRIPT_PATH/read_button.sh A B X Y)
echo "Button ${BUTTON} is pressed"
echo

if [ $BUTTON == 'A' ] ; then
    echo "OK we pause here."
    echo "This line will be shown in showOutput. Press select to exit now."
    # close stdout
    exec 1<&-
    echo "This line will NOT be shown in showOutput."
    return 0
elif [ $BUTTON == 'B' ] ; then
    # send magic keyword to close showOutput
    echo __EXIT__
    sleep 3
    echo "exit now"
    return 0
fi

echo "Please press D-pad to continue:"
BUTTON=$($SCRIPT_PATH/read_button.sh LEFT RIGHT UP DOWN)
echo "Button ${BUTTON} is pressed"
echo

echo "Please ANY button to continue:"
BUTTON=$($SCRIPT_PATH/read_button.sh)
echo "Button ${BUTTON} is pressed"
echo

echo "Please press MENU to exit:"
BUTTON=$($SCRIPT_PATH/read_button.sh MENU)
echo "Button ${BUTTON} is pressed"

return 0
