#!/bin/sh
echo $0 $*
progdir=`dirname "$0"`
cd $progdir
export LD_LIBRARY_PATH=/usr/trimui/lib/
./fneditor
