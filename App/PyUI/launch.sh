#!/bin/sh

#ENV Variables
export PYSDL2_DLL_PATH="/mnt/sdcard/App/PyUI/dll"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/miyoo/lib"
killall -STOP MainUI
/mnt/sdcard/spruce/flip/bin/python3 /mnt/sdcard/App/PyUI/main-ui/MainUI.py
killall -CONT MainUI
