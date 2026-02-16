#!/bin/bash
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# PortMaster header
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

# Source the controls and device info
source $controlfolder/control.txt
source $controlfolder/device_info.txt

# Source custom mod files from the portmaster folder
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
# Pull the controller configs for native controls
get_controls

# Directory setup
GAMEDIR=/mnt/SDCARD/App/Moonlight/ports/moonlightnew
MOONDIR=/mnt/SDCARD/App/Moonlight/ports/moonlightnew/moonlight
CONFDIR="$GAMEDIR/conf/"
mkdir -p "$GAMEDIR/conf"

# Enable logging
#> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

cd $GAMEDIR

# Set the XDG environment variables for config & savefiles for LOVE
export XDG_DATA_HOME="$CONFDIR"
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"

# Run LOVE
chmod +x ./love
chmod +x ./moonlight/moonlight
$GPTOKEYB "love" &
./love gui

# Cleanup LOVE
$ESUDO kill -9 $(pidof gptokeyb)
$ESUDO systemctl restart oga_events &
printf "\033c" > /dev/tty0

# Change directory to moonlight
cd "$MOONDIR"

# Fetch the command after running LOVE
COMMAND=$(<command.txt)

# Set the library path and SDL controls
export LD_LIBRARY_PATH="$MOONDIR/libs:$LD_LIBRARY_PATH"

# Run Moonlight using eval to handle the command from command.txt
$GPTOKEYB "moonlight" &
eval "./moonlight $COMMAND"

rm -f command.txt  # Remove command.txt after use

# Cleanup Moonlight
"$ESUDO" kill -9 $(pidof gptokeyb)
"$ESUDO" systemctl restart oga_events &
printf "\033c" > /dev/tty0
