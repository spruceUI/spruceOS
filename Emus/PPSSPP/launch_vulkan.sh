#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
progdir181_vulkan=$progdir/PPSSPP_1.18.1_vulkan
cd $progdir181_vulkan
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir181_vulkan

echo "=============================================="
echo "==================== PPSSPP  ================="
echo "=============================================="

./cpufreq.sh
./cpuswitch.sh


export HOME=$progdir181_vulkan
./PPSSPPSDL_vulkan "$*"
