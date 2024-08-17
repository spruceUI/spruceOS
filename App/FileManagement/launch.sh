#!/bin/sh
export HOME=`dirname "$0"`
export LD_LIBRARY_PATH=lib:$LD_LIBRARY_PATH

cd $HOME
./DinguxCommander
sync
