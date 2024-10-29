#!/bin/sh

MAC=$(ifconfig wlan0 | grep HWaddr | grep -o "..:..:..:..:..:..")
echo -n "MAC address: ${MAC}"