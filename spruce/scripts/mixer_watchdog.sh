#!/bin/sh

. /mnt/SDCARD/spruce/scripts/audioFunctions.sh

reset_playback_pack

# TODO: will need to fix for brick and tsp
JACK_PATH=/sys/class/gpio/gpio150/value

[ "$PLATFORM" = "Flip" ] && while true; do
  /mnt/SDCARD/spruce/bin64/inotifywait -e modify "$SYSTEM_JSON" >/dev/null 2>&1 &
  PID_INOTIFY=$!

  /mnt/SDCARD/spruce/bin64/gpiowait $JACK_PATH &
  PID_GPIO=$!

  wait -n

  log_message "*** mixer watchdog: change detected" -v

  kill $PID_INOTIFY $PID_GPIO 2>/dev/null

  set_playback_path
done
