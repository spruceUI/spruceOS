#!/bin/sh

pid=`ps | grep cmd_to_run | grep -v grep | sed 's/[ ]\+/ /g' | cut -d' ' -f2`
ppid=$pid
echo pid is $pid
while [ "" != "$pid" ] ; do
   ppid=$pid   
   pid=`pgrep -P $ppid`
done

if [ "" != "$ppid" ] ; then
   kill -9 $ppid
fi
echo ppid $ppid quit
