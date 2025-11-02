#!/bin/sh
echo "============= scene CPUFREQ ============"

while [ true ]
do
	case "$1" in
	1 ) 
		echo "cpu save"
		echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
		echo -n "1200000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 
		echo -n "1008000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 
		;;
	0 )
		echo "cpu normal"
		echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor                                                    
		echo -n "1008000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 
		echo -n "2000000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 
		;;
	*)
		;;
	esac
	sleep 5
done
