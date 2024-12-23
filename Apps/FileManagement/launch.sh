#!/bin/sh
cd $(dirname "$0")

export LD_LIBRARY_PATH=$(dirname "$0")/lib64:$LD_LIBRARY_PATH
./DinguxCommanderBrick
