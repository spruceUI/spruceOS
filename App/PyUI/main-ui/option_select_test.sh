#!/bin/bash

export PYSDL2_DLL_PATH="/mnt/SDCARD/App/PyUI/dll"
export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/miyoo/lib"

/mnt/SDCARD/spruce/flip/bin/python3 OptionSelectUI.py "title" /mnt/sdcard/options.json