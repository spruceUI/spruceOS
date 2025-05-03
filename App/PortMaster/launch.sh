#!/bin/sh

#ENV Variables
export PYSDL2_DLL_PATH="/mnt/sdcard/Persistent/portmaster/site-packages/sdl2dll/dll"
export PATH="/mnt/sdcard/spruce/flip/bin/:/mnt/sdcard/Persistent/portmaster/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/sdcard/spruce/flip/lib/:$LD_LIBRARY_PATH"
export HOME="/mnt/sdcard/Saves/flip/home"

if [ ! -d "/mnt/sdcard/Persistent/portmaster" ] ; then
  cp -R /mnt/sdcard/App/PortMaster/.portmaster /mnt/sdcard/Persistent/portmaster
fi

# Until PM-GUI is updated we need to override where spruce stores things
# Just replacing the entire file. This should go away soon
rm /mnt/sdcard/Persistent/portmaster/PortMaster/miyoo/PortMaster.txt
rm /mnt/sdcard/Persistent/portmaster/PortMaster/miyoo/control.txt
rm /mnt/sdcard/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py
cp /mnt/sdcard/App/PortMaster/PortMaster.txt /mnt/sdcard/Persistent/portmaster/PortMaster/miyoo/PortMaster.txt
cp /mnt/sdcard/App/PortMaster/control.txt /mnt/sdcard/Persistent/portmaster/PortMaster/miyoo/control.txt
cp /mnt/sdcard/App/PortMaster/config.py /mnt/sdcard/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py

rm /mnt/sdcard/Saves/flip/home/.local/share/PortMaster/control.txt
cp /mnt/sdcard/App/PortMaster/control.txt /mnt/sdcard/Saves/flip/home/.local/share/PortMaster/control.txt

#Launch port master
cd /mnt/sdcard/Persistent/portmaster/PortMaster/miyoo/

cp "/mnt/sdcard/App/PortMaster/.portmaster/device_info_Miyoo_Miyoo Flip.txt" "/mnt/sdcard/Saves/flip/home/device_info_Miyoo_Miyoo Flip.txt"

./PortMaster.txt &> /mnt/sdcard/Saves/spruce/portmaster.log

# Fix images to be spruce compatible
/mnt/sdcard/App/PortMaster/update_images.sh &> /mnt/sdcard/Saves/spruce/updated_images.log


