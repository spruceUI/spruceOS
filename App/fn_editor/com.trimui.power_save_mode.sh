echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo -n "1200000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq 
echo -n "1008000" > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq 