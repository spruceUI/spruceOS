#!/bin/sh

# TODO: pull log into its own file?
. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

# TODO: this should be generalized at some point, probably when supporting the brick
reset_playback_pack() {
  log_message "*** audioFunctions.sh: reset playback path" -v

  current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
  system_json_volume=$(cat $SYSTEM_JSON | grep -o '"vol":\s*[0-9]*' | grep -o [0-9]*)
  current_vol_name="SYSTEM_VOLUME_$system_json_volume"
  amixer sset 'SPK' 1% > /dev/null
  amixer cset name='Playback Path' 0 > /dev/null
  amixer cset name='Playback Path' "$current_path" > /dev/null
  amixer sset 'SPK' "$SYSTEM_VOLUME_${!current_vol_name}"% > /dev/null
}

# TODO: just pull this into mixer? tbd on if this needs to be used anywhere else
set_playback_path() {
  volume_lv=$(amixer cget name='SPK Volume' | grep  -o ": values=[0-9]*" | grep -o [0-9]*)
  log_message "*** audioFunctions.sh: Volume level: $volume_lv" -v

  jack_status=$(cat /sys/class/gpio/gpio150/value) # 0 connected, 1 disconnected
  log_message "*** audioFunctions.sh: Jack status: $jack_status" -v

  # 0 OFF, 2 SPK, 3 HP
  playback_path=$([ $jack_status -eq 1 ] && echo 2 || echo 3)
  [ "$volume_lv" = 0 ] && [ "$playback_path" = 2 ] && playback_path=0
  log_message "*** audioFunctions.sh: Playback path: $playback_path" -v

  current_path=$(amixer cget name="Playback Path" | grep  -o ": values=[0-9]*" | grep -o [0-9]*)

  amixer cset name='Playback Path' "$playback_path" > /dev/null
  # if coming off mute, ensure that there's a change so that volume doesn't spike
  ( (( current_path == 0 )) || (( current_path != playback_path )) ) && [ ! "$playback_path" = 0 ] \
    && amixer sset 'SPK' 1% > /dev/null && amixer sset 'SPK' "$volume_lv%" > /dev/null
}

