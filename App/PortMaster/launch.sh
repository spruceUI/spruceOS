#!/bin/sh
export PYSDL2_DLL_PATH="/mnt/sdcard/MIYOO_EX/site-packages/sdl2dll/dll"
export PATH="/mnt/sdcard/bin/:$PATH"
export LD_LIBRARY_PATH="/mnt/sdcard/lib/:$LD_LIBRARY_PATH"
export HOME="/mnt/sdcard"
cd /sdcard/MIYOO_EX/PortMaster/PortMaster/miyoo
./PortMaster.txt > portmaster.log
