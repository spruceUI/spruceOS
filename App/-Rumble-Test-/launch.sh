#!/bin/sh

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

display -t "full power"
vibrate 1000
sleep 1
display_kill

display -t "75% power"
timer=0
while [ $timer -lt 1000 ]; do
	vibrate 3
	sleep 0.004
	timer=$(($timer + 4 ))
done
display_kill

display -t "66% power"
timer=0
while [ $timer -lt 1000 ]; do
	vibrate 2
	sleep 0.003
	timer=$(($timer + 3 ))
done
display_kill

display -t "50% power"
timer=0
while [ $timer -lt 1000 ]; do
	vibrate 1
	sleep 0.002
	timer=$(($timer + 2 ))
done
display_kill

display -t "33% power"
timer=0
while [ $timer -lt 1000 ]; do
	vibrate 1
	sleep 0.003
	timer=$(($timer + 3 ))
done
display_kill

display -t "25% power"
timer=0
while [ $timer -lt 1000 ]; do
	vibrate 1
	sleep 0.004
	timer=$(($timer + 4 ))
done
display_kill

display -t "10% power"
timer=0
while [ $timer -lt 1000 ]; do
	vibrate 1
	sleep 0.01
	timer=$(($timer + 10 ))
done
display_kill