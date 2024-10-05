Usage: easyConfig config_file [-t title]

-t:     title of the config window.
-h,--help       show this help message.


UI control: L1/R1: Select group, Up/Down: Select item, Left/Right: change value, B: Exit

The config file should contains lines of config settings, in the following format:
"NAME" "DESCRIPTION" "POSSIBLE_VALUES" "DISPLAY_VALUES" "CURRENT_VALUE" ["COMMANDS"]

NAME: short name used in options file.
DESCRIPTION: description shown in config window.
POSSIBLE_VALUES: possible values of setting.
DISPLAY_VALUES: corresponding display texts of possible values shown in config window.
CURRENT_VALUES: current value of setting, should be one of the display values.
COMMANDS: optional commands to be executed on exit if the setting value is changed.

POSSIBLE_VALUES, DISPLAY_VALUES and COMMANDS are values seperated by '|'. Example lines of config file:

"-s" "Text scrolling speed" "10|20|30" "Slow|Normal|Fast" "Fast"
"-t" "Display title at start" "on|off" "on|off" "on"

settings can be organized into groups, which displayed as multiple tags in config window. To define a group use insert line with the following format:

[GROUP_NAME] [OPTIONAL_OUTPUT_FILENAME]

Note that the square brackets are part of input. Any setting items after the group definition will be assigned to the group. OPTIONAL_OUTPUT_FILENAME is the filename of optional output file. Output option file is generated when program exit, which containing pairs of NAME and VALUE, can be utilized as option list for calling another program. Example output options:

-s 10 -b off -t on -ts 4 -n on

Config file is updated with new values when program exit.
