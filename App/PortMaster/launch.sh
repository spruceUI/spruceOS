#!/bin/sh
export PYSDL2_DLL_PATH="/mnt/sdcard/MIYOO_EX/site-packages/sdl2dll/dll"
export PATH="/mnt/sdcard/spruce/flip/bin/:$PATH"
export LD_LIBRARY_PATH="/mnt/sdcard/spruce/flip/lib/:$LD_LIBRARY_PATH"
export HOME="/mnt/sdcard/spruce/flip/home"
cd /sdcard/MIYOO_EX/PortMaster/PortMaster/miyoo
./PortMaster.txt &> /mnt/sdcard/spruce/logs/portmaster.log
/mnt/sdcard/App/PortMaster/update_images.sh


