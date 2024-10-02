Usage: easyConfig config_file [-t title] [-o options_file]

-t:     title of the config window.
-o:     output options file, contains single line of options generated from config file.
-h,--help       show this help message.


UI control: Up/Down: Select item, Left/Right: change value, B: Exit

The config file should contains lines of config settings, in the following format:
"NAME" "DESCRIPTION" "POSSIBLE_VALUES" "DISPLAY_VALUES" "CURRENT_VALUE" ["COMMANDS"]

NAME: short name used in options file.
DESCRIPTION: description shown in config window.
POSSIBLE_VALUES: possible values of setting.
DISPLAY_VALUES: corresponding display texts of possible values shown in config window.
CURRENT_VALUES: current value of setting, should be one of the display values.
COMMANDS: optional commands to be executed after the setting value is updated.

POSSIBLE_VALUES, DISPLAY_VALUES and COMMANDS are values seperated by '|'. Example lines of config file:

"-s" "Text scrolling speed" "10|20|30" "Slow|Normal|Fast" "Fast"
"-t" "Display title at start" "on|off" "on|off" "on"

Config file is updated when program exit.

Output option file is generated when program exit, which containing pairs of NAME and VALUE, can be utilized as option list for calling another program. Example output option file:

-s 10 -b off -t on -ts 4 -n on
