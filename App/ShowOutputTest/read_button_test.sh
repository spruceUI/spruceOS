#!/bin/sh

SCRIPT_PATH="/mnt/SDCARD/spruce/scripts"

echo "Please press Button A or B or X or Y to continue:"
BUTTON=$($SCRIPT_PATH/read_button.sh A B X Y)
echo "Button ${BUTTON} is pressed"
echo

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
