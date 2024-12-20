#!/bin/sh
#set > /tmp/env.txt
echo $0 $*
progdir=`dirname "$0"`
cd $progdir
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir

echo "=============================================="
echo "==================== PPSSPP  ================="
echo "=============================================="

./cpufreq.sh
./cpuswitch.sh

export HOME=/mnt/SDCARD
export SDL_GAMECONTROLLERCONFIG_FILE=/mnt/SDCARD/Emus/PPSSPP/assets/gamecontrollerdb.txt
#export SDL_AUDIODRIVER=dsp   //disable 20231031 for sound suspend issue


export SDL_GAMECONTROLLERCONFIG_FILE=/mnt/SDCARD/Emus/PPSSPP/assets/gamecontrollerdb.txt
#export PATH=/usr/sbin:/usr/bin:/sbin:/bin
#export SHLVL=2
export LD_LIBRARY_PATH=./:/mnt/SDCARD:/mnt/SDCARD/lib:/mnt/UDISK:/usr/trimui/lib/:/usr/miyoo/lib:/customer/lib/:/config/lib/:/lib:/usr/lib::/mnt/SDCARD/Emus/PPSSPP
export OLDPWD=/mnt/SDCARD/Emus/PPSSPP
set > /tmp/env.txt
./PPSSPPSDL_gl "$*"

