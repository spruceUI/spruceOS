#!/bin/sh

IP=$(ifconfig | grep -o "inet addr:[0-9|\.]*" | grep -o "[0-9|\.]*")

if [ -z $IP ]; then
    echo -n "WIFI not connected"
else
    echo -n "IP address: ${IP}"
fi