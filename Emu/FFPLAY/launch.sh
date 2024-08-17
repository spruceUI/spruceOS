#!/bin/sh
mydir=`dirname "$0"`

export HOME=$mydir
export PATH=$mydir/bin:$PATH
export LD_LIBRARY_PATH=$mydir/libs:/usr/miyoo/lib:/usr/lib:$LD_LIBRARY_PATH

cd $mydir
ffplay -vf transpose=2 -fs -i "$1"
