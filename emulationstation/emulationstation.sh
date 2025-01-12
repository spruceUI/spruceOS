#!/bin/sh

export LD_LIBRARY_PATH=/usr/miyoo/lib

runifnecessary(){
    cnt=0
    #a=`ps | grep $1 | grep -v grep`
    a=`pgrep $1`
    while [ "$a" == "" ] && [ $cnt -lt 8 ] ; do 
	   echo try to run $2 `cat /proc/uptime`
	   $2 $3 &
       sleep 0.5
	   cnt=`expr $cnt + 1`
       a=`pgrep $1`
    done
}

esdir="$(dirname $0)"
while true; do
    runifnecessary "miyoo_inputd" /usr/miyoo/bin/miyoo_inputd

    rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown
    "$esdir/emulationstation" "$@"
    ret=$?
    [ -f /tmp/es-restart ] && continue
    if [ -f /tmp/es-sysrestart ]; then
        rm -f /tmp/es-sysrestart
        reboot
        break
    fi
    if [ -f /tmp/es-shutdown ]; then
        rm -f /tmp/es-shutdown
        poweroff
        break
    fi
    break
done
exit $ret
