#!/bin/sh

systemctl enable wpa_supplicant
systemctl start wpa_supplicant
/mnt/SDCARD/spruce/scripts/runtime.sh
