===== read_button.sh =====
Read single button press event and print pressed button to STDOUT.

Usage: read_button.sh [A|B|X|Y|L1|L2|R1|R2|UP|DOWN|LEFT|RIGHT|START|SELECT|MENU|VOLUMN_UP|VOLUMN_DOWN]

Example:

echo "Please press Button A or B or X or Y to continue:"
BUTTON=$($SCRIPT_PATH/read_button.sh A B X Y)
echo "Button ${BUTTON} is pressed"


===== showOutput =====

Usage: showOutput [-d] [-f n] [-h|--help] [-i] [-t title] [-w] [-x n]

-d:         disable useer interaction.
-f:         specify font size as n (default is 20).
-h, --help: show this usage help message.
-i:         display instruction in the output window.
-t:         display title in the output window.
-w:         word-wrap when a line is overflow.
-x:         exit after n second when EOF is read.
