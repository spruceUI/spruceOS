======== CLI ========

Usage: easyConfig config_file [-o] [-m MODE] [-p index] [-t title]

-h,--help       show this help message.
-m:     filter setting items with specified MODE, multiple modes can be specified.
-o:     generate options only.
-p:     show i-th group only (first group index = 1).
-t:     title of the config window.

======== CONTROL ========

UI control: L1/R1: Select group, Up/Down: Select item, Left/Right/A: Change value, B: Save and exit, Select: Cancel and exit


======== CONFIG FILE - SETTING ITEM ========

The config file should contains lines of config settings, in the following format:
"NAME" "DESCRIPTION" "POSSIBLE_VALUES" "DISPLAY_VALUES" "CURRENT_VALUE" ["COMMANDS"] ["INFO_COMMAND"]

NAME: short name used in options file.
DESCRIPTION: description shown in config window.
POSSIBLE_VALUES: possible values of setting.
DISPLAY_VALUES: corresponding display texts of possible values shown in config window.
CURRENT_VALUE: current value of setting, should be one of the display values.
COMMANDS: optional commands to be executed on exit if the setting value is changed.
INFO_COMMAND: optional command to be executed once the setting value is changed. It should return minor info text to be displayed

POSSIBLE_VALUES, DISPLAY_VALUES and COMMANDS are values seperated by '|'. 
CURRENT_VALUE can be a command to be executed with return value as initial setting value.
INFO_COMMAND should be a command that takes the zero-based index (e.g. 0, 1, 2) representing the current setting value.
So it should return the corresponding minor info text according the current setting value.
Example lines of config file:

"-s" "Text scrolling speed" "10|20|30" "Slow|Normal|Fast" "Fast"
"-t" "Display title at start" "on|off" "on|off" "on" "echo ON|echo OFF"
"" "Enable SSH" "|" "on|off" "$SSH$ check" "$SSH$ on|$SSH$ off" "$SSH$"

======== CONFIG FILE - HARDCODED MINOR INFO ========

You can hardcode minor info text for a setting item by add extra line below a setting item.
The minor info should be in the format @"Minor info". Examples such as:

@"this is hardcoded minor text"
@"User: spruce, password: happygaming"

======== CONFIG FILE - DYNAMIC INFO ========

Dynamic information text can be added as single item, which should be a command to be executed on start. The command should print output to stdout to set the information text. To define an information text add a line with the following format

%"the_commond_to_run_on_start.sh"

======== CONFIG FILE - ALIAS ========

You can define aliases to replace long commands or file path with short names. 
Aliases should be defined in the format $NAME=value$ placed at the top of config file.
Example aliases such as:

$FLAGS=/mnt/SDCARD/spruce/flags$
$CHECK=/mnt/SDCARD/spruce/scripts/checkFlag.sh$

And you can use aliases as part of the commands in CURRENT_VALUE COMMANDS and INFO_COMMAND".
Example setting item lines with using aliases:

""    "Run GS on start" "|" "on|off" "$CHECK$ gs.boot" "touch $FLAGS$/gs.boot|rm -f $FLAGS$/gs.boot"


======== CONFIG FILE - GROUP ========

Settings can be organized into groups, which displayed as multiple tags in config window. To define a group use insert line with the following format:

[GROUP_NAME] [OPTIONAL_OUTPUT_FILENAME]

Note that the square brackets are part of input. Any setting items after the group definition will be assigned to the group. OPTIONAL_OUTPUT_FILENAME is the filename of optional output file. Output option file is generated when program exit, which containing pairs of NAME and VALUE, can be utilized as option list for calling another program. Example output options:

-s 10 -b off -t on -ts 4 -n on

======== CONFIG FILE - MODE TAGS ========

Setting items can be tagged by mode names and filtered with the -m option. A setting item is always shown if no tag is assigned. To tag a setting item, insert the mode names before the setting item with the following format:

<MODE_NAME_1> <MODE_NAME_2> ...



Config file is updated with new values when program exit.
