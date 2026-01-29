#!/bin/sh

INFO=$(cat /proc/cpuinfo 2> /dev/null)
case $INFO in
    *"sun8i"*) export PLATFORM="A30" ;;
    *"TG5040"*)	export PLATFORM="SmartPro" ;;
    *"TG3040"*)	export PLATFORM="Brick"	;;
    *"TG5050"*)	export PLATFORM="SmartProS"	;;
    *"0xd05"*) export PLATFORM="Flip" ;;
    *"0xd04"*) export PLATFORM="Pixel2" ;;
    *) export PLATFORM="MiyooMini" ;;
esac

#ENV Variables
case "$PLATFORM" in
    Flip|SmartProS)
        export PYSDL2_DLL_PATH="/mnt/SDCARD/Persistent/portmaster/site-packages/sdl2dll/dll"
        export PATH="/mnt/SDCARD/spruce/flip/bin:/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:$LD_LIBRARY_PATH"
        export HOME="/mnt/SDCARD/Saves/flip/home"
        ;;
    Brick|SmartPro)
        export PYSDL2_DLL_PATH="/mnt/SDCARD/spruce/brick/sdl2"
        export PATH="/mnt/SDCARD/spruce/flip/bin:/mnt/SDCARD/Persistent/portmaster/bin:$PATH"
        export LD_LIBRARY_PATH="/mnt/SDCARD/spruce/flip/lib:$LD_LIBRARY_PATH"
        export HOME="/mnt/SDCARD/Saves/flip/home"
        ;;
    Pixel2)
        export HOME="/mnt/SDCARD/Saves/flip/home"
        /usr/bin/start_portmaster.sh &> /mnt/SDCARD/Saves/spruce/portmaster.log
        /mnt/SDCARD/App/PortMaster/update_images.sh &> /mnt/SDCARD/Saves/spruce/updated_images.log
        rm /mnt/SDCARD/Roms/PORTS/gamelist.*
        exit 0
        ;;
esac

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

# Hide pm_message for miyoo as it creates some issues for us (jpg and broken ports)
FILE="/mnt/SDCARD/Persistent/portmaster/PortMaster/mod_Miyoo.txt"
grep -q '^pm_message()' "$FILE" 2>/dev/null || \
echo 'pm_message() { echo "$1" > "$CUR_TTY"; }' >> "$FILE"
