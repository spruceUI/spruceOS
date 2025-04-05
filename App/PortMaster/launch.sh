#!/bin/sh
export PYSDL2_DLL_PATH="/mnt/sdcard/MIYOO_EX/site-packages/sdl2dll/dll"
export PATH="/mnt/sdcard/MIYOO_EX/bin/:$PATH"
export LD_LIBRARY_PATH="/mnt/sdcard/MIYOO_EX/lib/:$LD_LIBRARY_PATH"
cd /sdcard/MIYOO_EX/PortMaster/PortMaster/miyoo
./PortMaster.txt > portmaster.log
