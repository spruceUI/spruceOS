#!/bin/sh
echo running chroot mnt /bin/sh -c "/mnt/sdcard/Emu/PORT32/run_port.sh $1"
chroot mnt /bin/sh -c "/mnt/sdcard/Emu/PORT32/run_port.sh $1"
