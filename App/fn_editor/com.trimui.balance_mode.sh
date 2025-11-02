echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor                                                    
echo -n "1200000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 
echo -n "2000000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 