#!/bin/sh

info_dir="/mnt/SDCARD/RetroArch/.retroarch/cores"
core_info="$info_dir/${CORE}_libretro.info"
core_name=`awk '/corename/ {print $3}' "$core_info"`
core_name=`echo ${core_name} | tr -d '"'`
state_dir="/mnt/SDCARD/Saves/states/$core_name"
game_shortname="${GAME%.*}"
screenshot="$state_dir/${game_shortname}.state.auto.png"

rm "/mnt/SDCARD/.tmp_update/flags/gs_activated"

/mnt/SDCARD/.tmp_update/bin/display_text.elf "$screenshot" "$GAME" 5 40 bottom middle 640 ff ff ff
