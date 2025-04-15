#!/bin/sh

#ENV Variables
export PYSDL2_DLL_PATH="/sdcard/Roms/.portmaster/site-packages/sdl2dll/dll"
export PATH="/mnt/sdcard/spruce/flip/bin/:/mnt/sdcard/Roms/.portmaster/bin:$PATH"
export LD_LIBRARY_PATH="/mnt/sdcard/spruce/flip/lib/:$LD_LIBRARY_PATH"
export HOME="/mnt/sdcard/spruce/flip/home"

if [ ! -d "/sdcard/Roms/.portmaster" ] ; then
  cp -R /mnt/sdcard/App/PortMaster/.portmaster /sdcard/Roms/.portmaster
fi


# Until PM-GUI is updated we need to override where spruce stores things
# Just replacing the entire file. This should go away soon
rm /sdcard/Roms/.portmaster/PortMaster/miyoo/PortMaster.txt
rm /sdcard/Roms/.portmaster/PortMaster/miyoo/control.txt
rm /sdcard/Roms/.portmaster/PortMaster/pylibs/harbourmaster/config.py
cp /mnt/sdcard/App/PortMaster/PortMaster.txt /sdcard/Roms/.portmaster/PortMaster/miyoo/PortMaster.txt
cp /mnt/sdcard/App/PortMaster/control.txt /sdcard/Roms/.portmaster/PortMaster/miyoo/control.txt
cp /mnt/sdcard/App/PortMaster/config.py /sdcard/Roms/.portmaster/PortMaster/pylibs/harbourmaster/config.py

rm /mnt/sdcard/spruce/flip/home/.local/share/PortMaster/control.txt
cp /mnt/sdcard/App/PortMaster/control.txt /mnt/sdcard/spruce/flip/home/.local/share/PortMaster/control.txt

#Launch port master
cd /sdcard/Roms/.portmaster/PortMaster/miyoo/
./PortMaster.txt &> /mnt/sdcard/spruce/logs/portmaster.log

# Fix images to be spruce compatible
/mnt/sdcard/App/PortMaster/update_images.sh


