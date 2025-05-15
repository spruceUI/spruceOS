#!/bin/sh

#ENV Variables
export PYSDL2_DLL_PATH="/mnt/SDCARD/Persistent/portmaster/site-packages/sdl2dll/dll"
export PATH="/mnt/SDCARD/spruce/flip/bin/:/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib/:$LD_LIBRARY_PATH"
export HOME="/mnt/SDCARD/Saves/flip/home"

if [ ! -d "/mnt/SDCARD/Persistent/portmaster" ] ; then
  cp -R /mnt/SDCARD/App/PortMaster/.portmaster /mnt/SDCARD/Persistent/portmaster
fi

# Until PM-GUI is updated we need to override where spruce stores things
# Just replacing the entire file. This should go away soon
rm /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/PortMaster.txt
rm /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/control.txt
rm /mnt/SDCARD/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py
cp /mnt/SDCARD/App/PortMaster/PortMaster.txt /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/PortMaster.txt
cp /mnt/SDCARD/App/PortMaster/control.txt /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/control.txt
cp /mnt/SDCARD/App/PortMaster/config.py /mnt/SDCARD/Persistent/portmaster/PortMaster/pylibs/harbourmaster/config.py

rm /mnt/SDCARD/Saves/flip/home/.local/share/PortMaster/control.txt
cp /mnt/SDCARD/App/PortMaster/control.txt /mnt/SDCARD/Saves/flip/home/.local/share/PortMaster/control.txt

#Launch port master
cd /mnt/SDCARD/Persistent/portmaster/PortMaster/miyoo/

cp "/mnt/SDCARD/App/PortMaster/.portmaster/device_info_Miyoo_Miyoo Flip.txt" "/mnt/SDCARD/Saves/flip/home/device_info_Miyoo_Miyoo Flip.txt"

./PortMaster.txt &> /mnt/SDCARD/Saves/spruce/portmaster.log

# Fix images to be spruce compatible
/mnt/SDCARD/App/PortMaster/update_images.sh &> /mnt/SDCARD/Saves/spruce/updated_images.log


