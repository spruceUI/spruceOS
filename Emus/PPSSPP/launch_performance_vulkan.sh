#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
progdir181_vulkan=$progdir/PPSSPP_1.18.1_vulkan
cd $progdir181_vulkan
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$progdir181_vulkan

echo "=============================================="
echo "==================== PPSSPP  ================="
echo "=============================================="

#./cpufreq.sh
echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo 1416000 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
#./cpuswitch.sh
echo 1 > /sys/devices/system/cpu/cpu0/online
echo 1 > /sys/devices/system/cpu/cpu1/online
echo 1 > /sys/devices/system/cpu/cpu2/online
echo 0 > /sys/devices/system/cpu/cpu3/online

export HOME=$progdir181_vulkan
./PPSSPPSDL_vulkan "$*"
