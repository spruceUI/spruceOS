#!/bin/sh

#ENV Variables
export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/miyoo/lib"
killall -STOP MainUI
/mnt/SDCARD/spruce/flip/bin/python3 /mnt/SDCARD/App/PyUI/main-ui/MainUI.py > /mnt/SDCARD/Saves/spruce/PyUI.txt 2>&1
killall -CONT MainUI
