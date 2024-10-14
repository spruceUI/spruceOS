#!/bin/sh

emu_path="/mnt/SDCARD/Emu"
roms_path="/mnt/SDCARD/Roms"
show_img="/mnt/SDCARD/App/EMUFRESH/refreshing.png"

echo ============ EMUFRESH ============
echo $(date)
if [ ! -f "$show_img" ]; then
    echo "Image file not found at $show_img"
else
    show "$show_img" &
fi

if [ $(mount | grep SDCARD | cut -d"(" -f 2 | cut -d"," -f1 ) == "ro" ]; then
  mount -o remount,rw /dev/mmcblk0p1 /mnt/SDCARD
fi

delete_cache_files() {
    find $roms_path -name "*cache6.db" -exec rm {} \;
}

update_config_file() {
  local v_config="$(grep -E "^\{" "$2")"
  if [ $1 = 0 ]; then
    sed -i 's/^{*$/{{/' "$2"
  elif [ $1 = 1 ]; then
    sed -i 's/^{{*$/{/' "$2"
  fi
}

delete_cache_files

find "$emu_path" -type f -name 'config.json' | while read -r file; do
  v_system=$(basename "$(dirname "$file")")
  if [ $v_system == "MEDIA" ]; then
    v_rom=$(find "$roms_path/$v_system/" -type f -o -iname *. | grep -iv Imgs | grep -icE -m1 "/*")
  else
    v_type=$(cat $file | grep -m1 extlist | cut -d ":" -f 2 | sed "s/,//" | sed "s/ //" | sed "s/\	//" | sed 's/|\"/\"/g' | sed 's/\"//' | sed 's/\"//')
    v_rom=$(find "$roms_path/$v_system" -type f -o -iname *. | grep -iv txt | grep -icE -m1 "$v_type")
  fi
  #echo "$v_system" "$v_rom" "$v_type"
  update_config_file "$v_rom" "$file"
done
killall -9 MainUI
echo $(date)
# Alpha#9751 with love for SPRUCE by tenlevels
# +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
