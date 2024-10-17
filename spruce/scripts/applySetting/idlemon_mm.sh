#!/bin/sh

# If no arg, read the timeout_value from stored settings
if [ -z "$1" ]; then
  if [ -f /mnt/SDCARD/spruce/settings/idlemon_mainmenu ]; then
    timeout_value=$(cat /mnt/SDCARD/spruce/settings/idlemon_mainmenu)
  else
    timeout_value="Off" 
  fi
else
  timeout_value="$1"
fi

# Kill all processes with 'idlemon' and 'MainUI' in the name
pgrep -f 'idlemon.*MainUI' | xargs kill -9

# Set the timeout and check params
case "$timeout_value" in
  Off)
    exit 0
    ;;
  2m)
    idle_time=120
    idle_check=10
    ;;
  5m)
    idle_time=300
    idle_check=20
    ;;
  10m)
    idle_time=600
    idle_check=40
    ;;
  *)
    exit 1
    ;;
esac

# Start idlemon 
idlemon -p MainUI -t "$idle_time" -c "$idle_check" -s "/mnt/SDCARD/spruce/scripts/idlemon_actionWrapper.sh" -i > /dev/null &
