#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_playback_path() {
  count=$1

  volume_lv=$(amixer cget name='SPK Volume' | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
  (( count % 10 == 0)) && log_message "Volume level: $volume_lv" -v

  jack_status=$(cat /sys/class/gpio/gpio150/value)
  (( count % 10 == 0)) && log_message "Jack status: $jack_status" -v

  playback_path=$([ $jack_status -eq 1 ]  && echo 'SPK' || echo 'HP')
  [ "$volume_lv" = 0 ] && [ "$playback_path" = 'SPK' ] && playback_path='OFF'
  (( count % 10 == 0)) && log_message "Playback path: $playback_path" -v

  current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)

  amixer cset name='Playback Path' "$playback_path" > /dev/null
  # if coming off mute, ensure that there's a change so that volume doesn't spike
  (( current_path == 0 )) && [ ! "$playback_path" = "OFF" ] && amixer sset 'SPK' 1% > /dev/null && amixer sset 'SPK' 5% > /dev/null
}

count=0
# TODO: will need to fix for brick and tsp
[ "$PLATFORM" = "Flip" ] && while true; do
  set_playback_path $count
  ((count++))
done
